# Feedback and annotations

Feedback is anchored to a stable subject rather than to a loose page:

| Subject | Anchor |
|---|---|
| Map | `document.id` |
| Map shape | `document.id#node.id` |
| Process | `process.id` |
| Opportunity | `opportunity.id` |
| Initiative | `initiative.id` |
| Meeting | `meeting.id` |
| Mining case | `dataset.id#caseHash` |

A comment records author, time, body, @mentions and resolved state. Replies use
the root comment id. Resolution is on the root thread; deleting a thread deletes
its replies.

Entry points are the **Feedback** button on Maps (map and shape), Discoveries,
Opportunities, Improvements, Meetings and the mining case card. **Improve →
Feedback** is the inbox: Open / Resolved / All, with a thread sheet for reply,
resolve, reopen and delete.

Comments are local annotation, not a write to Flightdeck Maps, Atlas or PDF
Studio. There is no sync or notification delivery yet; @mentions are stored as
typed and are not resolved against a person directory.


The web form has the same thread semantics and a map/shape comment panel; its
state is in-memory in this build, so a reload resets comments. The macOS app
persists through SwiftData.
