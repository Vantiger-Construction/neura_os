# Voluntary wellbeing usability review

Status: protocol and in-app feedback tooling prepared; no participants recruited,
clinical review completed, or treatment benefit established by this change.

## Purpose and boundaries

Determine whether people can understand the app, choose a small activity, stop,
control storage and find human help. This is a usability review, not diagnosis,
treatment, crisis monitoring or a trial of clinical effectiveness. Any subsequent
study of health outcomes needs its own qualified review, consent and governance.

NIMH describes both the potential and the limitations of mental-health technology,
including privacy, evidence and collaboration with mental-health professionals:
[Technology and the Future of Mental Health Treatment](https://www.nimh.nih.gov/health/topics/technology-and-the-future-of-mental-health-treatment).
For cognitive accessibility, use W3C's guidance on reducing interruptions and
helping people focus: [Help Users Focus](https://www.w3.org/WAI/WCAG2/supplemental/objectives/o5-user-focus/).
Neither source endorses Neura or proves that these features improve health.

## Before a session

- Invite adults with varied lived experiences, access needs and familiarity with
  technology, and separately invite qualified mental-health professionals to
  review wording, boundaries and routes to human help. Invitations and any
  compensation require an explicitly approved process; this document sends none.
- Give a plain-language explanation of tasks, optional feedback, intended use of
  findings and the right to skip or stop without losing access to the app.
- Agree what minimal notes may be kept, who can see them, how long they will be
  retained, and how a participant can request their removal. Default to no audio,
  video, screenshots, diagnosis history or identifiable participant records.
- Use the isolated sample-data Windows build, record its exact revision and
  confirm the preview banner. Never ask for real journal text or credentials.
  Agree a support/stop procedure with a qualified facilitator; do not use an
  emergency or distress disclosure as an opportunity to continue testing.

## Short, optional tasks

1. Find an activity for a fictional person who wants a quiet pause. Describe what
   you expect it to do, then start and stop it. There is no required completion.
2. Increase text size, reduce motion and navigate using the participant's usual
   input method. Check focus order, labels, clipping and whether Escape/back is
   understandable. Do not claim screen-reader acceptance from widget tests.
3. Set suggestions to appear only on request, exclude an activity, then review
   and forget those choices. Ask what was saved and what remained available.
4. Select one sample check-in, prepare a question, review/edit the appointment
   summary and choose whether to copy it to the demo clipboard. Confirm that
   unselected records and notes are absent. Explain production clipboard limits.
5. Find human-support information without contacting anybody. Check whether the
   person understands the app's limits and can distinguish a draft from a sent
   message. Do not trigger a phone, message, clinic or emergency workflow.
6. Optionally preview usability feedback, remove anything private and decide
   whether to share it. Leaving or stopping must clear the temporary draft.

Allow the participant to choose the order, take a break, decline every task or
end the session. Avoid streaks, persuasive completion prompts or promises of
improvement. Ask neutral questions such as “What did you expect?” rather than
questions that suggest the desired answer.

## Evidence and follow-up

Record only consented, de-identified usability observations: task attempted or
skipped, independent completion or assistance, confusing labels, unexpected
storage/export expectations and access barriers. Avoid retaining a person's
free-form health disclosures. The optional in-app report can be edited before
copying; it is never automatically submitted or linked to check-in history.

Prioritize inadvertent disclosure, inability to stop, hidden persistence and
misunderstanding of human-help routes before cosmetic requests. Reproduce each
accepted defect with synthetic fixtures, fix it and repeat the affected task
with voluntary participants. Keep automated checks and observed human results
separate, with build identity and limitations for each.

Release review should explicitly state who reviewed wording and accessibility,
which tasks were observed, unresolved concerns, supported environments and the
limits of the evidence. A small positive usability session does not establish
clinical safety, efficacy or suitability for everybody. Obtain separate approval
before recruiting, storing feedback externally, sharing findings or changing
the clinic/profile holds. PR #181 remains excluded from merge decisions.
