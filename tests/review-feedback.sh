#!/usr/bin/env bash
# Run with: bash tests/review-feedback.sh
set -eu
plugin="$(cd "$(dirname "$0")/.." && pwd)/github-review-requests.2m.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Exercise the SwiftBar entry point with an isolated cache and read-only GitHub fixtures.
# The first PR has two pages of reviews and requests. The second has no formal reviews.
gh() {
  case "$1 $2" in
    'api user') echo me ;;
    'search prs')
      if [ "$3" = '--reviewed-by=@me' ]; then
        if [ -e "$work_dir/no-pending" ]; then echo '[]'; return; fi
        echo '[{"url":"https://example.org/pending","author":{"login":"alice"},"repository":{"nameWithOwner":"org/test"},"number":2}]'
      else
        if [ -e "$work_dir/rev-error" ]; then return 1; fi
        echo '[]'
      fi ;;
    'api graphql')
      case "$*" in
        *ISSUE_COMMENT*|*IssueComment*) return 1 ;;
      esac
      case "$*" in
        *'after=reviews-2'*) page=$work_dir/reviews-2 ;;
        *'after=events-2'*) page=$work_dir/events-2 ;;
        *'after=prs-2'*) page=$work_dir/prs-2 ;;
        *) page=$work_dir/prs-1 ;;
      esac
      cat "$page" ;;
    'api repos/org/test/pulls/2/reviews') echo COMMENTED ;;
    *) return 1 ;;
  esac
}

render() (
  set +e
  export HOME="$work_dir"
  # Source the executable to inject gh above even with SwiftBar's Homebrew-first PATH.
  source "$plugin"
)
expect_line() { printf '%s\n' "$output" | grep -Fxq "$1"; }
reject_text() {
  if [[ "$output" == *"$1"* ]]; then
    echo "Unexpected menu text: $1" >&2
    return 1
  fi
}

jq -n '
  def page($nodes; $next): {nodes: $nodes, pageInfo: {hasNextPage: ($next != null), endCursor: $next}};
  def review($login; $state; $at; $comment): {
    id: $login, author: {__typename: "User", login: $login}, viewerDidAuthor: ($login == "me"),
    state: $state, submittedAt: $at, bodyText: "", url: ("review/" + $login),
    comments: {nodes: (if $comment then [{url: ("line/" + $login)}] else [] end)}
  };
  {data: {parent: {items: page([{
    id: "pr1", title: "Feedback PR", isDraft: true, url: "pull/1", author: {login: "me"},
    reviews: page([
      review("alice"; "CHANGES_REQUESTED"; "01"; false),
      review("bob"; "COMMENTED"; "01"; true),
      review("carol"; "CHANGES_REQUESTED"; "01"; false),
      review("dave"; "COMMENTED"; "01"; false),
      review("me"; "COMMENTED"; "01"; true),
      (review("ci"; "COMMENTED"; "01"; true) | .author.__typename = "Bot")
    ]; "reviews-2"), events: page([]; "events-2")
  }]; "prs-2")}}}' > "$work_dir/prs-1"

jq -n '{data: {parent: {items: {nodes: [{
  id: "pr2", title: "Conversation only", isDraft: false, url: "pull/2", author: {login: "me"},
  reviews: {nodes: [], pageInfo: {hasNextPage: false}},
  events: {nodes: [], pageInfo: {hasNextPage: false}}
}], pageInfo: {hasNextPage: false}}}}}' > "$work_dir/prs-2"

jq -n '{data: {parent: {items: {nodes: [{
  id: "approval", state: "APPROVED", submittedAt: "02", author: {__typename: "User", login: "carol"},
  comments: {nodes: [{url: "line/on-approval"}]}
}], pageInfo: {hasNextPage: false}}}}}' > "$work_dir/reviews-2"

jq -n '{data: {parent: {items: {nodes: [
  {__typename: "ReviewRequestedEvent", actor: {login: "me"}, requestedReviewer: {login: "alice"}, createdAt: "02"},
  {__typename: "ReviewRequestedEvent", actor: {login: "someone-else"}, requestedReviewer: {login: "bob"}, createdAt: "02"}
], pageInfo: {hasNextPage: false}}}}}' > "$work_dir/events-2"

# The same feedback becomes visible on the first refresh after leaving draft.
output=$(render)
expect_line 'REV:0+1 | color=orange'
reject_text 'Feedback PR'
reject_text '@bob'
jq '.data.parent.items.nodes[0].isDraft = false' "$work_dir/prs-1" > "$work_dir/ready"
mv "$work_dir/ready" "$work_dir/prs-1"
output=$(render)
expect_line 'REV:0+1 FIX:1 | color=orange'
expect_line '@bob | size=11 color=gray href=line/bob'
reject_text '@alice'
reject_text '@carol'
reject_text '@dave'
reject_text '@ci'
reject_text '@me'
reject_text 'Conversation only'

# A reply after approval and a body-only review after re-request both reopen their author's feedback.
jq '.data.parent.items.nodes += [
  {id: "reply", state: "COMMENTED", submittedAt: "03", author: {__typename: "User", login: "carol"},
   bodyText: "", comments: {nodes: [{url: "line/reply"}]}},
  {id: "feedback", state: "COMMENTED", submittedAt: "03", author: {__typename: "User", login: "alice"},
   bodyText: "Please check", url: "review/again", comments: {nodes: []}}
]' "$work_dir/reviews-2" > "$work_dir/new-reviews"
mv "$work_dir/new-reviews" "$work_dir/reviews-2"
output=$(render)
expect_line 'REV:0+1 FIX:1 | color=orange'
expect_line '@carol | size=11 color=gray href=line/reply'
expect_line '@alice | size=11 color=gray href=review/again'

# A failed continuation must discard partial FIX results and preserve REV.
mv "$work_dir/events-2" "$work_dir/saved-events"
output=$(render)
expect_line 'REV:0+1 FIX:? | color=orange'
reject_text '@bob'
mv "$work_dir/saved-events" "$work_dir/events-2"
output=$(render)
expect_line 'REV:0+1 FIX:1 | color=orange'
touch "$work_dir/rev-error"
output=$(render)
expect_line 'REV:? FIX:1 | color=orange'
expect_line '@bob | size=11 color=gray href=line/bob'
rm "$work_dir/rev-error"
touch "$work_dir/no-pending"
output=$(render)
expect_line 'REV:0 FIX:1 | color=orange'
cp "$work_dir/prs-2" "$work_dir/prs-1"
output=$(render)
expect_line 'REV:0 | color=gray'
echo 'review-feedback tests passed'
