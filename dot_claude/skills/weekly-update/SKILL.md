---
name: weekly-update
description: "Draft Felipe's weekly update for the #weekly-updates Slack channel by gathering the week's work from git, GitHub, Linear, Slack, Notion, and Google Calendar. Use when asked to write, draft, or post a weekly update / week recap."
---

# Weekly Update

Draft a concise, bulleted weekly update for the `#weekly-updates` Slack
channel (ID: `C0A8SN1S7PD`). Teammates typically post Thursday or Friday.

## Step 1: Determine the date range

Default to Monday of the current week through today. If the user mentions
PTO, a short week, or a different range, use that instead. Check
`#weekly-updates` for the user's last post — if it exists, start the range
the day after it.

## Step 2: Gather context (run all of these in parallel)

Load MCP tool schemas via ToolSearch first. If a connector only exposes
`authenticate` tools, it is NOT authenticated — tell the user to run
`/mcp` and authenticate it, then continue with the remaining sources.

1. **Git** — commits by the user across all branches:
   `git log --all --author="Felipe" --since=<start> --pretty=format:"%h %ad %s" --date=short`
2. **GitHub** — PRs authored this period:
   `gh pr list --author "@me" --state all --limit 20 --json number,title,state,createdAt,url,isDraft`
   For each relevant PR, the description's "What does this PR do?" section
   is the best summary source. Note review discussions worth mentioning
   (e.g. reviewer-found bugs that were fixed).
3. **Linear** — `list_issues` with `assignee: "me"` and `updatedAt` set to
   the period (e.g. `-P7D`). Capture status (Done / In Review / In
   Progress) and issue URLs.
4. **Slack** — `slack_search_public_and_private` with
   `from:<@U0B70RY2A0K> after:<start>` sorted by timestamp. Look for:
   design discussions in DMs, pairing/collab threads, things shared in
   channels. This surfaces non-ticket work (e.g. tooling, architecture
   jams) that git/Linear miss.
5. **Notion** — `notion-search` for meeting notes or docs the user touched
   this week (filter by created date range).
6. **Google Calendar** — `list_events` for the period, primary calendar.
   Useful for pairing sessions, onsites, interviews. Known issue: the
   connector may return "insufficient authentication scopes" — if so,
   tell the user to re-authenticate via `/mcp` and proceed without it.
7. **Unblocked** — `context_research` as a supplementary sweep, useful as
   a fallback for any source above that is unavailable.

## Step 3: Match house style

Fetch the most recent few posts in `#weekly-updates`
(`in:#weekly-updates after:<a week or two ago>`) and mirror the format.
House style as of June 2026:

- Plain Slack bullets, one line each, sub-bullets for detail
- Casual tone, light emoji, first person
- Inline raw links to Linear issues and PRs
- Common shape: shipped → in review/in progress → collabs/misc → next up

## Step 4: Draft and confirm

- Keep it short — one bullet per work item, not per commit. Match the
  length of teammates' posts (typically 4–8 lines): one line per theme,
  no "why it mattered" clauses, ticket keys instead of explanations,
  at most a couple of links.
- Lead with shipped/merged work, then in-review, then non-ticket items
  (pairing, tooling, discussions), then a "next up" line.
- Credit collaborators by name where natural (reviewer catches, jams).
- Show the draft in chat with a short note on sources used and anything
  that couldn't be checked (unauthenticated connectors).
- Offer to post it: use `slack_send_message_draft` to `#weekly-updates`
  (ID `C0A8SN1S7PD`) so the user can review in Slack before sending.
  Never post directly without the user confirming the final text.

### Slack formatting gotchas (both have bitten before)

- Markdown list syntax does NOT convert — `- ` hyphens post literally.
  Use literal `•` bullets and `  ◦` sub-bullets, bare URLs, and avoid
  any markdown that depends on conversion.
- Broadcast mentions resolve at send time, even from a draft: a naked
  `@channel`/`@here`/`@everyone` used as a *reference* in the text
  ("...instead of @channel") will ping the whole channel when sent.
  Backtick-fence every such occurrence; same for group/user mentions
  not meant to notify anyone.
