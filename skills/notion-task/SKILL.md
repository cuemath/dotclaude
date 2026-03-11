---
name: notion-task
description: Create and manage Notion tasks in the Cuemath PED Features database with proper epic linking
allowed-tools: mcp__claude_ai_Notion__notion-search, mcp__claude_ai_Notion__notion-fetch, mcp__claude_ai_Notion__notion-create-pages, mcp__claude_ai_Notion__notion-update-page
argument-hint: "[vertical/epic] [task description]"
---

# Notion Task Manager

Create and manage Notion tasks for the Cuemath engineering team. Uses conversation context to build well-structured tasks in the PED Features database.

## Notion Workspace Structure

**Teamspace:** PED Teamspace
**Features Database** (data source): `collection://ed895725-81c9-479a-b021-b9eb18c0c04e`
**Epics Database** (data source): `collection://942163d6-1e75-4f48-932f-056190906657`

### Verticals

| Vertical | Notion Page ID | Description |
|----------|---------------|-------------|
| Tutoring | `13e8897c-aec7-8158-b722-eaf6e01f7897` | Classroom experience — Learning Plan, Chapter Page, Extra Practice |
| Mathgym | `13e8897c-aec7-813d-9849-e4e64b1a44e1` | Math practice and workout features |
| Prep | `13e8897c-aec7-81cb-8b61-e70f2da3f75f` | Exam prep platform |
| CX | `13e8897c-aec7-810d-832e-d4e29bfb08e1` | Customer experience |

### Tutoring Epics

| Epic | Notion Page ID | Use When |
|------|---------------|----------|
| Tutoring: Bugs and Debts | `14b8897c-aec7-8072-ae9c-c9afa2068c06` | Bugs, tech debt, race conditions, errors, fixes |
| Tutoring: Enhancements | `1708897c-aec7-80f1-8d1f-dfa96e5ca380` | Improvements to existing tutoring features |
| Tutoring: Student Delight | `1618897c-aec7-80b8-ae04-d3369acb564d` | Features that improve student experience |
| Tutoring: Dashboards | `2ca8897c-aec7-8049-8455-e83673437db9` | Dashboard and reporting features |
| Tutoring: Purging legacy | `3128897c-aec7-80d9-b388-d6971942071e` | Removing legacy code and migrations |
| Tutoring: Misc Epic | `1618897c-aec7-8080-9ac7-e76236cbb254` | Features not mapped to a specific epic yet |

## Steps

### Step 1: Determine the action

- If the user wants to **create** a task — proceed to Step 2.
- If the user wants to **update** an existing task — search for it using `notion-search`, fetch it, then update properties or content using `notion-update-page`. Skip to Step 5.

### Step 2: Determine Vertical and Epic

**If the user specifies a vertical/epic:** Use exactly what they specify (case-insensitive match).

**If not specified, auto-detect from context:**

1. **Repo context** — `concepts` repo defaults to **Tutoring** vertical.
2. **Issue type mapping:**
   - Bug / Error / Race condition / Crash / Data issue → **Tutoring: Bugs and Debts**
   - Performance / Refactor / Tech debt / Legacy removal → **Tutoring: Purging legacy**
   - New feature / Enhancement to existing feature → **Tutoring: Enhancements**
   - Student UX improvement → **Tutoring: Student Delight**
   - Dashboard / Reporting / Analytics → **Tutoring: Dashboards**
   - Doesn't fit above → **Tutoring: Misc Epic**
3. **Non-Tutoring verticals** — Search Notion for epics under that vertical:
   ```
   Use notion-search with query "<Vertical>:" in the epics data source
   ```

**If still unsure:** Ask the user which vertical and epic to use before creating.

### Step 3: Analyze context and build task content

Review the current session to extract:
- **What happened** — the error/issue/feature request
- **Root cause** — why it happened (if known)
- **Impact** — severity and user impact
- **Affected files** — code paths involved
- **Fix options** — proposed solutions (if discussed)

### Step 4: Create the task

Create a page in the Features database:

```
Parent: data_source_id = ed895725-81c9-479a-b021-b9eb18c0c04e

Properties:
  - Name: <concise title, under 80 chars>
  - Status: "Not started"
  - Epic: "[\"https://www.notion.so/<epic-page-id-without-dashes>\"]"
```

**Content template:**

```markdown
## Summary
<2-3 sentence description>

**Occurred:** <date/time if known>

## Root Cause
<Explanation of why this happened. Include timeline from logs if available.>

## Impact
**Severity:** <Low/Medium/High>
<User-facing impact description>

## Fix Options
1. **<Option name>** — <description>
2. **<Option name>** — <description>

## Files
- `<file_path>` — `<function_name>()` (line <N>)
```

Omit sections that have no relevant information (e.g., skip "Root Cause" for a new feature request).

### Step 5: Confirm

After creating or updating the task, return:
- The Notion page URL
- The vertical and epic it was created/updated under
- A one-line summary

## Do NOT:

- Create orphan tasks without an Epic link
- Over-explain each step
- Ask for confirmation between steps (unless the epic is ambiguous)
- Offer follow-up suggestions
- Include empty sections in the task content
