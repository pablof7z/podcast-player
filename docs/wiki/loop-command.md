---
title: Loop Command
slug: loop-command
topic: agent-system
summary: "Interval parsing follows these rules in order: - A leading token matching ^\d+[smhd]$ is parsed as the interval; the remainder becomes the prompt. - A trailing"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-13
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:16ac1219-405e-4d37-bcba-f2ad417a7e1e
---

# Loop Command

## /loop Command

Interval parsing follows these rules in order:
- A leading token matching ^\d+[smhd]$ is parsed as the interval; the remainder becomes the prompt.
- A trailing 'every <N><unit>' or 'every <N> <unit-word>' clause is parsed as the interval and stripped from the prompt when followed by a time expression.
- When no interval is parsed, /loop enters dynamic self-paced mode using the entire input as the prompt.
- If the parsed prompt is empty, /loop shows usage '/loop [interval] <prompt>' and stops. <!-- [^16ac1-3] -->

When the interval is ≥60 minutes or the input uses daily phrasing, /loop offers a cloud schedule option before local scheduling. <!-- [^16ac1-4] -->

If the user picks 'Cloud schedule', /loop invokes the 'schedule' skill via the Skill tool with the original input verbatim and then stops without calling CronCreate or executing the prompt immediately. <!-- [^16ac1-5] -->

If the user picks 'This session only' but the trigger was daily phrasing with no parsed interval, /loop does not call CronCreate and instead explains that a daily-cadence loop won't fire before session close, suggesting Cloud schedule or a shorter explicit interval. <!-- [^16ac1-6] -->

In fixed-interval mode, /loop converts the interval to a cron expression using these mapping rules: Nm where N≤59 → */N * * * *; Nh where N≤23 → 0 */N * * *; Nd → 0 0 */N * *; Ns → ceil(N/60)m. When an interval doesn't cleanly divide its unit, /loop rounds to the nearest clean interval and informs the user before scheduling. <!-- [^16ac1-7] -->

/loop calls CronCreate with recurring:true and the parsed prompt verbatim, then confirms the schedule details including the job ID, cron expression, human-readable cadence, the 7-day auto-expiry, and how to cancel with CronDelete. Recurring cron jobs auto-expire after 7 days. If the cloud-offer question was not shown (neither trigger condition applied), the confirmation includes the italicized line '_Runs until you close this session · For durable cloud-based loops, use /schedule_'; otherwise this line is omitted. <!-- [^16ac1-8] -->

/loop immediately executes the parsed prompt after scheduling, invoking slash commands via the Skill tool. <!-- [^16ac1-9] -->

In dynamic mode, /loop confirms whether it is self-pacing, whether a Monitor is the primary wake signal, that the task was run now, and what fallback delay was chosen, written as text before calling ScheduleWakeup. Then /loop runs the parsed prompt immediately, arms a persistent Monitor if the next run is gated on an observable event (skipping if a Monitor is already running via TaskList check), and calls ScheduleWakeup as the last action of the turn. <!-- [^16ac1-10] -->

In dynamic mode with a Monitor armed, ScheduleWakeup's delaySeconds serves as a fallback heartbeat (1200–1800s); without a Monitor, it serves as the cadence based on observations. The ScheduleWakeup prompt parameter is the full original /loop input verbatim, prefixed with '/loop '. <!-- [^16ac1-11] -->

When woken by a task-notification in dynamic mode, /loop handles the event in context and calls ScheduleWakeup again with the same prompt and 1200–1800s fallback delay. <!-- [^16ac1-12] -->

To stop a dynamic-mode loop, /loop omits the ScheduleWakeup call and TaskStops any armed Monitor, sending a one-line outcome via PushNotification unless the user explicitly told it to stop. <!-- [^16ac1-13] -->
