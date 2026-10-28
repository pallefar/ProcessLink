import type { KGKind, MethodKey, Predicate, Route, SavingsStage, WasteType } from './types'

export const WASTE_LABEL: Record<WasteType, string> = {
  waiting: 'Waiting',
  rework: 'Rework',
  overProcessing: 'Over-processing',
  handoffs: 'Handoffs',
  contextSwitching: 'Context switching',
  defects: 'Defects',
  unusedTalent: 'Unused talent',
  backlog: 'Backlog',
}

export const WASTE_DIGITAL: Record<WasteType, string> = {
  waiting: 'Queue time, approvals waiting, batch waits',
  rework: 'Re-opening a case, correcting a record, repeating a check',
  overProcessing: 'Extra approvals, duplicate data entry, unnecessary checks',
  handoffs: 'Work passed between teams, systems or tickets',
  contextSwitching: 'Jumping between applications to finish one task',
  defects: 'Wrong data, failed validation, returned cases',
  unusedTalent: 'Skilled people doing copy-paste or chasing',
  backlog: 'Open cases growing faster than they close',
}

export const ROUTE_LABEL: Record<Route, string> = {
  eliminate: 'Eliminate',
  simplify: 'Simplify',
  standardize: 'Standardize',
  automate: 'Automate',
  leave: 'Leave as-is',
}

export const ROUTE_DETAIL: Record<Route, string> = {
  eliminate: 'Stop doing the step at all; question the requirement first.',
  simplify: 'Keep the outcome, remove the extra checks and data entry.',
  standardize: 'Make the best path the only path, with a human control where required.',
  automate: 'Only after eliminate, simplify and standardize are done.',
  leave: 'Nothing worth changing; keep it visible and monitored.',
}

export const METHOD_TITLE: Record<MethodKey, string> = {
  '5s': '5S workplace organization',
  vsm: 'Value stream mapping',
  standardWork: 'Standard work',
  smed: 'SMED / quick changeover',
  kaizen: 'Kaizen event',
  a3: 'A3 problem solving',
  hoshin: 'Hoshin deployment',
  dailyManagement: 'Daily management',
  tpm: 'Total productive maintenance',
  errorProofing: 'Error proofing',
}

export const METHOD_SUMMARY: Record<MethodKey, string> = {
  '5s': 'Organize the workspace so the right information is where the work happens.',
  vsm: 'Map the flow end to end, separate value from wait, and size the gap.',
  standardWork: 'Define the current best sequence, then measure adherence against it.',
  smed: 'Cut changeover and setup time between cases, products or queues.',
  kaizen: 'A focused, time-boxed team event that removes one known waste.',
  a3: 'One page: background, target, cause, countermeasure, result.',
  hoshin: 'Connect improvement work to the few breakthrough objectives that matter.',
  dailyManagement: "See today's performance against target, every day, at the point of work.",
  tpm: 'Keep the tools and data pipelines that carry the work reliable.',
  errorProofing: 'Make the mistake hard to make instead of asking people to try harder.',
}

export const STAGE_LABEL: Record<SavingsStage, string> = {
  estimated: 'Estimated',
  committed: 'Committed',
  validated: 'Validated',
}

export const STAGE_DETAIL: Record<SavingsStage, string> = {
  estimated: 'Calculated from mined data. Not a claim.',
  committed: 'An owner and a target date have signed up.',
  validated: 'Before/after evidence checked by a named validator.',
}

export const KG_LABEL: Record<KGKind, string> = {
  process: 'Process',
  step: 'Step',
  application: 'Application',
  role: 'Role',
  site: 'Site',
  valueStream: 'Value stream',
  opportunity: 'Opportunity',
  initiative: 'Initiative',
  savingsRecord: 'Savings record',
  hoshinObjective: 'Hoshin objective',
  document: 'Document / SOP',
  meeting: 'Meeting',
  decision: 'Decision',
  action: 'Action',
}

export const PREDICATE_LABEL: Record<Predicate, string> = {
  performedIn: 'performed in',
  uses: 'uses',
  handsOffTo: 'hands off to',
  variantOf: 'variant of',
  ownedBy: 'owned by',
  measuredBy: 'measured by',
  addressedBy: 'addressed by',
  realizesSavings: 'realizes savings',
  alignedToObjective: 'aligned to objective',
  documentedIn: 'documented in',
  hasOpportunity: 'has opportunity',
  discussedIn: 'discussed in',
  assignedTo: 'assigned to',
}

export const MEETING_LABEL: Record<import('./types').MeetingKind, string> = {
  dailyHuddle: 'Daily huddle',
  kaizen: 'Kaizen event',
  a3Review: 'A3 review',
  leadership: 'Leadership review',
  workshop: 'Workshop',
  oneToOne: '1:1',
}

export const BLOCK_LABEL: Record<import('./types').BlockKind, string> = {
  heading: 'Heading',
  text: 'Text',
  bullet: 'Bullet',
  checklist: 'To-do',
  decision: 'Decision',
  action: 'Action',
  callout: 'Callout',
  link: 'Link',
}

export const KG_TONE: Record<import('./types').KGKind, string> = {
  process: 'blue',
  step: 'teal',
  application: 'blue',
  role: 'grey',
  site: 'grey',
  valueStream: 'teal',
  opportunity: 'orange',
  initiative: 'purple',
  savingsRecord: 'green',
  hoshinObjective: 'red',
  document: 'grey',
  meeting: 'purple',
  decision: 'green',
  action: 'orange',
}
