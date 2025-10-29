---
description: Review current state and plan a specified task from task-master.
arguments: $ARGUMENTS # eg. review task 4
---

# Objective

Review the @README.md, @CLAUDE.md, @/specs/README.md, ALL project specs in @specs/, and then review the request from the user in the <additional_context></additional_context> section below. Finally, review the current state of the codebase to determine the best way to handle the user's request and think hard to make an implementation plan for the user to review and approve before getting started. Remember, ALWAYS keep it MVP simple and do NOT over-engineer things at this early stage of development. We can extend features later as needed.

<additional_context>
$ARGUMENTS
</additional_context>
