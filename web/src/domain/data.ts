import type {
  AuditEntry, BlockKind, GovernanceItem, Initiative, KGEdge, KGNode, Meeting, MeetingBlock,
  Opportunity, PrivacyPolicy, Process, Step,
} from './types'
import { initiativeLine, recommendMethod, routeFor } from './rules'

/** A fixed clock keeps screenshots and tests deterministic. */
export const NOW = new Date('2026-10-28T09:00:00Z')
const iso = (daysAgo: number) => new Date(NOW.getTime() - daysAgo * 86_400_000).toISOString()
const due = (daysAhead: number) => new Date(NOW.getTime() + daysAhead * 86_400_000).toISOString()

export const POLICY: PrivacyPolicy = {
  minimumGroupSize: 10,
  retentionDays: 400,
  provider: 'Local (on device)',
  region: 'EU',
  purpose: 'processImprovement',
  dataOwner: 'CI Manager (role)',
}

type StepInput = {
  name: string; role: string; application: string; minutes: number; handoffs: number
  rework: number; waste: Step['waste']; evidence: number; aligned?: boolean
}

const step = (processId: string, index: number, input: StepInput): Step => ({
  id: `step-${processId}-${index}`,
  kgId: `kg-step-${processId}-${index}`,
  standardAligned: input.aligned ?? true,
  name: input.name,
  role: input.role,
  application: input.application,
  minutes: input.minutes,
  handoffs: input.handoffs,
  rework: input.rework,
  waste: input.waste,
  evidence: input.evidence,
})

export const PROCESSES: Process[] = [
  {
    id: 'p-triage', name: 'Customer case triage', site: 'Manila', businessUnit: 'Customer Experience',
    valueStream: 'Issue-to-resolution', owner: 'Customer Care Lead',
    summary: 'Cases arrive from the portal, chat and e-mail. Triage classifies and routes them; resolvers summarise the history by hand before they can act.',
    applications: ['ServiceNow', 'Outlook', 'Salesforce'],
    people: 56, annualHours: 4270, cycleMinutes: 18, reworkRate: 0.22, handoffs: 3, adherence: 0.55,
    confidence: 0.9, maturity: 2, classification: 'internal', status: 'discovered', statusReason: '',
    standard: 'SOP CX-07 Case triage', standardVersion: 'v2.4', staleDays: 1,
    kypId: 'kyp-proc-p-triage', kgId: 'kg-proc-p-triage',
    steps: [
      step('p-triage', 0, { name: 'Intake from portal', role: 'Customer Care', application: 'ServiceNow', minutes: 3, handoffs: 0, rework: 0.03, waste: 'waiting', evidence: 1284 }),
      step('p-triage', 1, { name: 'Classify and prioritise', role: 'Triage Agent', application: 'ServiceNow', minutes: 5, handoffs: 0, rework: 0.16, waste: 'overProcessing', evidence: 1201 }),
      step('p-triage', 2, { name: 'Route to resolver group', role: 'Triage Agent', application: 'ServiceNow', minutes: 2, handoffs: 1, rework: 0.09, waste: 'handoffs', evidence: 1198 }),
      step('p-triage', 3, { name: 'Summarise case history', role: 'Resolver', application: 'Salesforce', minutes: 18, handoffs: 0, rework: 0.14, waste: 'unusedTalent', evidence: 976 }),
      step('p-triage', 4, { name: 'Update the customer', role: 'Resolver', application: 'Outlook', minutes: 4, handoffs: 1, rework: 0.07, waste: 'contextSwitching', evidence: 921 }),
      step('p-triage', 5, { name: 'Close and survey', role: 'Customer Care', application: 'ServiceNow', minutes: 2, handoffs: 0, rework: 0.05, waste: 'rework', evidence: 1104 }),
    ],
    variants: [
      { name: 'Portal, standard', share: 0.46, cycle: 14, rework: 0.16, path: 'Intake → Classify → Route → Resolve → Update → Close' },
      { name: 'E-mail with attachment', share: 0.28, cycle: 26, rework: 0.29, path: 'Intake → Classify → Route → Resolve → Update → Update → Close' },
      { name: 'Escalated priority', share: 0.18, cycle: 34, rework: 0.24, path: 'Intake → Classify → Route → Resolve → Escalate → Update → Close' },
      { name: 'Reopened case', share: 0.08, cycle: 51, rework: 0.46, path: 'Intake → Classify → Route → Resolve → Close → Intake → Route' },
    ],
  },
  {
    id: 'p-order', name: 'Order intake & validation', site: 'Bensheim', businessUnit: 'Customer Experience',
    valueStream: 'Order-to-cash', owner: 'Order Desk Lead',
    summary: 'Orders arrive by e-mail, EDI and the web shop. The desk re-keys, checks the customer master, validates pricing and releases credit holds before a sales order exists.',
    applications: ['Outlook', 'SAP S/4HANA', 'Salesforce'],
    people: 34, annualHours: 3180, cycleMinutes: 42, reworkRate: 0.28, handoffs: 6, adherence: 0.61,
    confidence: 0.91, maturity: 2, classification: 'internal', status: 'discovered', statusReason: '',
    standard: 'SOP O2C-04 Order intake', standardVersion: 'v6.2', staleDays: 3,
    kypId: 'kyp-proc-p-order', kgId: 'kg-proc-p-order',
    steps: [
      step('p-order', 0, { name: 'Receive order', role: 'Order Desk', application: 'Outlook', minutes: 6, handoffs: 0, rework: 0.05, waste: 'waiting', evidence: 412 }),
      step('p-order', 1, { name: 'Check customer master', role: 'Order Desk', application: 'SAP S/4HANA', minutes: 9, handoffs: 1, rework: 0.18, waste: 'rework', evidence: 398 }),
      step('p-order', 2, { name: 'Validate pricing', role: 'Pricing Analyst', application: 'Salesforce', minutes: 12, handoffs: 1, rework: 0.22, waste: 'overProcessing', evidence: 366 }),
      step('p-order', 3, { name: 'Release credit hold', role: 'Credit Manager', application: 'SAP S/4HANA', minutes: 4, handoffs: 1, rework: 0.05, waste: 'waiting', evidence: 121 }),
      step('p-order', 4, { name: 'Create sales order', role: 'Order Desk', application: 'SAP S/4HANA', minutes: 14, handoffs: 1, rework: 0.12, waste: 'contextSwitching', evidence: 402 }),
      step('p-order', 5, { name: 'Send confirmation', role: 'Order Desk', application: 'Outlook', minutes: 3, handoffs: 0, rework: 0.04, waste: 'rework', evidence: 389 }),
      step('p-order', 6, { name: 'Clear exception queue', role: 'Order Desk', application: 'Salesforce', minutes: 11, handoffs: 2, rework: 0.38, waste: 'handoffs', evidence: 187 }),
    ],
    variants: [
      { name: 'EDI straight-through', share: 0.31, cycle: 18, rework: 0.07, path: 'Receive → Master → Pricing → Create → Confirm' },
      { name: 'E-mail with manual pricing', share: 0.42, cycle: 47, rework: 0.31, path: 'Receive → Master → Pricing → Credit → Create → Confirm' },
      { name: 'Exception re-key from portal', share: 0.19, cycle: 76, rework: 0.44, path: 'Receive → Queue → Master → Pricing → Credit → Create → Queue' },
      { name: 'Credit-hold escalation', share: 0.08, cycle: 121, rework: 0.36, path: 'Receive → Master → Credit → Pricing → Create → Confirm' },
    ],
  },
  {
    id: 'p-invoice', name: 'Invoice exception handling', site: 'Wrocław', businessUnit: 'Finance Operations',
    valueStream: 'Procure-to-pay', owner: 'AP Team Lead',
    summary: 'Invoices that fail the three-way match land in an exception queue. Codes are free text, so the same defect is categorised differently by each specialist.',
    applications: ['SAP S/4HANA', 'Outlook', 'Coupa'],
    people: 22, annualHours: 2410, cycleMinutes: 31, reworkRate: 0.34, handoffs: 5, adherence: 0.58,
    confidence: 0.88, maturity: 2, classification: 'internal', status: 'discovered', statusReason: '',
    standard: 'SOP P2P-11 Exception coding', standardVersion: 'v3.0', staleDays: 9,
    kypId: 'kyp-proc-p-invoice', kgId: 'kg-proc-p-invoice',
    steps: [
      step('p-invoice', 0, { name: 'Open exception queue', role: 'AP Specialist', application: 'SAP S/4HANA', minutes: 4, handoffs: 0, rework: 0.08, waste: 'backlog', evidence: 512 }),
      step('p-invoice', 1, { name: 'Identify mismatch', role: 'AP Specialist', application: 'SAP S/4HANA', minutes: 11, handoffs: 0, rework: 0.29, waste: 'rework', evidence: 498 }),
      step('p-invoice', 2, { name: 'Ask buyer to confirm', role: 'AP Specialist', application: 'Outlook', minutes: 7, handoffs: 1, rework: 0.21, waste: 'handoffs', evidence: 441 }),
      step('p-invoice', 3, { name: 'Correct PO or invoice', role: 'Buyer', application: 'Coupa', minutes: 13, handoffs: 1, rework: 0.33, waste: 'defects', evidence: 402 }),
      step('p-invoice', 4, { name: 'Post and close', role: 'AP Specialist', application: 'SAP S/4HANA', minutes: 5, handoffs: 0, rework: 0.11, waste: 'overProcessing', evidence: 488 }),
    ],
    variants: [
      { name: 'Price mismatch', share: 0.44, cycle: 28, rework: 0.31, path: 'Queue → Identify → Buyer → Correct → Post' },
      { name: 'Missing receipt', share: 0.33, cycle: 39, rework: 0.41, path: 'Queue → Identify → Buyer → Correct → Post → Queue' },
      { name: 'Vendor master error', share: 0.23, cycle: 24, rework: 0.27, path: 'Queue → Identify → Correct → Post' },
    ],
  },
  {
    id: 'p-onboarding', name: 'Employee onboarding administration', site: 'Manila', businessUnit: 'HR Services',
    valueStream: 'Hire-to-retire', owner: 'HR Services Lead',
    summary: 'New-hire documents arrive by e-mail, are checked against a checklist and re-keyed into Workday. Missing documents restart the loop with the recruiter.',
    applications: ['Workday', 'Outlook', 'DocuSign'],
    people: 41, annualHours: 1890, cycleMinutes: 55, reworkRate: 0.19, handoffs: 4, adherence: 0.64,
    confidence: 0.83, maturity: 3, classification: 'internal', status: 'discovered', statusReason: '',
    standard: 'SOP H2R-02 Onboarding pack', standardVersion: 'v4.1', staleDays: 21,
    kypId: 'kyp-proc-p-onboarding', kgId: 'kg-proc-p-onboarding',
    steps: [
      step('p-onboarding', 0, { name: 'Receive new-hire pack', role: 'HR Coordinator', application: 'Outlook', minutes: 5, handoffs: 0, rework: 0.09, waste: 'waiting', evidence: 268 }),
      step('p-onboarding', 1, { name: 'Check document checklist', role: 'HR Coordinator', application: 'Workday', minutes: 16, handoffs: 0, rework: 0.24, waste: 'overProcessing', evidence: 261 }),
      step('p-onboarding', 2, { name: 'Chase missing documents', role: 'HR Coordinator', application: 'Outlook', minutes: 9, handoffs: 1, rework: 0.31, waste: 'handoffs', evidence: 174 }),
      step('p-onboarding', 3, { name: 'Create Worker record', role: 'HR Coordinator', application: 'Workday', minutes: 18, handoffs: 1, rework: 0.13, waste: 'rework', evidence: 255 }),
      step('p-onboarding', 4, { name: 'Send for e-signature', role: 'HR Coordinator', application: 'DocuSign', minutes: 4, handoffs: 1, rework: 0.06, waste: 'waiting', evidence: 247 }),
    ],
    variants: [
      { name: 'Complete pack first time', share: 0.52, cycle: 41, rework: 0.08, path: 'Receive → Check → Record → Sign' },
      { name: 'One missing document', share: 0.31, cycle: 68, rework: 0.24, path: 'Receive → Check → Chase → Record → Sign' },
      { name: 'Two or more missing', share: 0.17, cycle: 96, rework: 0.42, path: 'Receive → Check → Chase → Chase → Record → Sign' },
    ],
  },
  {
    id: 'p-supplier', name: 'Supplier master data maintenance', site: 'Guadalajara', businessUnit: 'Procurement',
    valueStream: 'Source-to-contract', owner: 'Procurement Operations Lead',
    summary: 'Supplier records are created per region with local conventions, then merged by hand when duplicates surface in payment runs.',
    applications: ['Coupa', 'SAP S/4HANA', 'Outlook'],
    people: 12, annualHours: 960, cycleMinutes: 26, reworkRate: 0.31, handoffs: 2, adherence: 0.7,
    confidence: 0.76, maturity: 3, classification: 'internal', status: 'discovered', statusReason: '',
    standard: 'SOP P2P-03 Supplier master', standardVersion: 'v2.2', staleDays: 12,
    kypId: 'kyp-proc-p-supplier', kgId: 'kg-proc-p-supplier',
    steps: [
      step('p-supplier', 0, { name: 'Receive supplier request', role: 'Procurement Analyst', application: 'Outlook', minutes: 6, handoffs: 0, rework: 0.07, waste: 'waiting', evidence: 142 }),
      step('p-supplier', 1, { name: 'Search existing records', role: 'Procurement Analyst', application: 'Coupa', minutes: 12, handoffs: 0, rework: 0.34, waste: 'rework', evidence: 139 }),
      step('p-supplier', 2, { name: 'Validate tax and bank data', role: 'Procurement Analyst', application: 'SAP S/4HANA', minutes: 17, handoffs: 1, rework: 0.28, waste: 'defects', evidence: 131 }),
      step('p-supplier', 3, { name: 'Merge duplicates', role: 'Master Data Steward', application: 'SAP S/4HANA', minutes: 22, handoffs: 1, rework: 0.39, waste: 'handoffs', evidence: 64 }),
    ],
    variants: [
      { name: 'New supplier', share: 0.61, cycle: 21, rework: 0.18, path: 'Request → Search → Validate' },
      { name: 'Duplicate merged', share: 0.39, cycle: 58, rework: 0.51, path: 'Request → Search → Validate → Merge → Validate' },
    ],
  },
  {
    id: 'p-contract', name: 'Contract clause review', site: 'Bensheim', businessUnit: 'Legal Operations',
    valueStream: 'Contract lifecycle', owner: 'Legal Operations Lead',
    summary: 'Standard clauses are reviewed against the playbook before signature. The group is small, so the aggregate is suppressed even locally.',
    applications: ['DocuSign', 'Outlook', 'Word'],
    people: 8, annualHours: 720, cycleMinutes: 74, reworkRate: 0.12, handoffs: 3, adherence: 0.66,
    confidence: 0.82, maturity: 2, classification: 'internal', status: 'suppressed',
    statusReason: 'Group of 8 is below the 10-person threshold. Only the existence of the process is shown.',
    standard: 'Playbook CL-01 Clause review', standardVersion: 'v1.9', staleDays: 6,
    kypId: 'kyp-proc-p-contract', kgId: 'kg-proc-p-contract',
    steps: [], variants: [],
  },
  {
    id: 'p-export', name: 'Export control screening', site: 'Bensheim', businessUnit: 'Trade Compliance',
    valueStream: 'Order-to-cash', owner: 'Trade Compliance Lead',
    summary: 'Orders are screened against restricted-party lists before release. The record is classified Restricted and never enters ProcessLink.',
    applications: ['SAP S/4HANA', 'Outlook'],
    people: 14, annualHours: 640, cycleMinutes: 12, reworkRate: 0.08, handoffs: 2, adherence: 0.88,
    confidence: 0.94, maturity: 4, classification: 'restricted', status: 'blocked',
    statusReason: 'Classified Restricted. The aggregate is blocked and no AI call may see it.',
    standard: 'SOP TC-02 Screening', standardVersion: 'v5.0', staleDays: 2,
    kypId: 'kyp-proc-p-export', kgId: 'kg-proc-p-export',
    steps: [], variants: [],
  },
]

type OppInput = Omit<Opportunity, 'processName' | 'site' | 'route' | 'method' | 'kgId' | 'status'> & { status?: Opportunity['status'] }

const opportunity = (input: OppInput): Opportunity => {
  const process = PROCESSES.find(p => p.id === input.processId)
  const base = {
    ...input,
    status: input.status ?? 'new',
    processName: process?.name ?? input.processId,
    site: process?.site ?? '',
    kgId: `kg-opp-${input.id}`,
  }
  const route = routeFor(base)
  return {
    ...base,
    route,
    method: recommendMethod(base.waste, route, base.statutory).method,
  }
}

export const OPPORTUNITIES: Opportunity[] = [
  opportunity({
    id: 'opp-pricing', title: 'Remove the duplicate pricing check before order approval',
    processId: 'p-order', waste: 'overProcessing', hours: 410, errorReduction: 18, effortWeeks: 3,
    risk: 2, alignment: 5, automation: 0.2, confidence: 0.9, statutory: false, owner: 'Order Desk Lead',
    rationale: 'Pricing is validated in Salesforce, then checked again in SAP by a second role. 18% of orders are re-opened because the two checks disagree.',
  }),
  opportunity({
    id: 'opp-exception', title: 'Automate the exception queue triage for order intake',
    processId: 'p-order', waste: 'handoffs', hours: 620, errorReduction: 22, effortWeeks: 6,
    risk: 3, alignment: 4, automation: 0.8, confidence: 0.86, statutory: false, owner: 'Order Desk Lead',
    rationale: '19% of orders take the exception path, with two extra handoffs and 44% rework on that path.',
  }),
  opportunity({
    id: 'opp-codes', title: 'Standardize invoice exception codes across Wrocław',
    processId: 'p-invoice', waste: 'rework', hours: 540, errorReduction: 25, effortWeeks: 4,
    risk: 2, alignment: 4, automation: 0.3, confidence: 0.88, statutory: false, owner: 'AP Team Lead',
    rationale: 'Codes are free text. The same defect is labelled three ways, so the queue cannot be analysed.',
  }),
  opportunity({
    id: 'opp-upload', title: 'Self-service upload for onboarding documents',
    processId: 'p-onboarding', waste: 'handoffs', hours: 390, errorReduction: 12, effortWeeks: 8,
    risk: 3, alignment: 3, automation: 0.6, confidence: 0.8, statutory: false, owner: 'HR Services Lead',
    rationale: '48% of packs need at least one chase. A self-service upload removes the chase, not the check.',
  }),
  opportunity({
    id: 'opp-summary', title: 'Agent assist for customer case summarization',
    processId: 'p-triage', waste: 'unusedTalent', hours: 780, errorReduction: 8, effortWeeks: 7,
    risk: 4, alignment: 4, automation: 0.85, confidence: 0.78, statutory: false, owner: 'Customer Care CI',
    rationale: 'Resolvers spend 18 minutes per case reading history that already exists in the case record. A human reviews every summary.',
  }),
  opportunity({
    id: 'opp-supplier', title: 'Merge duplicate supplier records at source',
    processId: 'p-supplier', waste: 'defects', hours: 210, errorReduction: 30, effortWeeks: 3,
    risk: 2, alignment: 2, automation: 0.5, confidence: 0.74, statutory: false, owner: 'Master Data Steward',
    rationale: '39% of supplier requests are duplicates. The root cause is the search step, not the merge step.',
  }),
  opportunity({
    id: 'opp-board', title: 'Daily management board for the triage backlog',
    processId: 'p-triage', waste: 'backlog', hours: 160, errorReduction: 5, effortWeeks: 2,
    risk: 1, alignment: 5, automation: 0.1, confidence: 0.9, statutory: false, owner: 'Customer Care Lead',
    rationale: 'The backlog grows every Monday and clears by Thursday. Nobody sees it until the queue breaches its SLA.',
  }),
  opportunity({
    id: 'opp-credit', title: 'Standard work for credit-hold decisions',
    processId: 'p-order', waste: 'overProcessing', hours: 130, errorReduction: 15, effortWeeks: 2,
    risk: 4, alignment: 4, automation: 0, confidence: 0.9, statutory: true, owner: 'Credit Manager',
    rationale: 'Credit release is a human control. Four people apply four thresholds, and the reasoning is not recorded.',
  }),
  opportunity({
    id: 'opp-paper', title: 'Eliminate the printed confirmation in order intake',
    processId: 'p-order', waste: 'waiting', hours: 95, errorReduction: 4, effortWeeks: 1,
    risk: 1, alignment: 3, automation: 0, confidence: 0.93, statutory: false, owner: 'Order Desk Lead',
    rationale: 'The confirmation is printed, signed and scanned although the e-mail is the legal record.',
  }),
  opportunity({
    id: 'opp-contract', title: 'Contract review checklist and clause library',
    processId: 'p-contract', waste: 'rework', hours: 120, errorReduction: 10, effortWeeks: 3,
    risk: 2, alignment: 3, automation: 0.2, confidence: 0.7, statutory: false, owner: 'Legal Operations Lead',
    rationale: 'Reviews restart when a clause is missing from the playbook. The group is below the display threshold.',
  }),
  opportunity({
    id: 'opp-export', title: 'Pre-check export screening inside the order flow',
    processId: 'p-export', waste: 'defects', hours: 180, errorReduction: 20, effortWeeks: 4,
    risk: 5, alignment: 5, automation: 0.4, confidence: 0.95, statutory: false, owner: 'Trade Compliance Lead',
    rationale: 'Screening happens after the order is built. This record is Restricted and blocked by policy.',
  }),
]

export const INITIATIVES: Initiative[] = [
  {
    id: 'ini-codes', title: 'A3: one exception-code list for invoice handling', opportunityId: 'opp-codes',
    processId: 'p-invoice', processName: 'Invoice exception handling', site: 'Wrocław', method: 'a3',
    owner: 'AP Team Lead', stage: 'act', due: iso(12), savingsHours: 540, savingsStage: 'validated',
    validatedBy: 'CI Manager, Wrocław', waste: 'rework',
    evidence: 'Before: 34% rework and 11 free-text codes over 8 weeks. After: 11% rework and one code list over 6 weeks. 540 h confirmed.',
    background: 'The exception queue could not be analysed because the same defect carried three labels.',
    target: 'One code list, 90% of exceptions categorised in week one, rework below 15%.',
    countermeasure: 'Fixed list, a weekly review, and the buyer confirmation moved into the same screen.',
    result: 'Rework 34% → 11%. 540 hours a year returned to the team.',
  },
  {
    id: 'ini-pricing', title: 'Kaizen: cut the second pricing check', opportunityId: 'opp-pricing',
    processId: 'p-order', processName: 'Order intake & validation', site: 'Bensheim', method: 'kaizen',
    owner: 'Ops Excellence Lead', stage: 'do', due: due(21), savingsHours: 410, savingsStage: 'committed',
    validatedBy: '', waste: 'overProcessing',
    evidence: '', background: 'Two pricing checks disagree on 18% of orders.',
    target: 'Remove the SAP re-check for orders above tolerance; keep a sampled audit.',
    countermeasure: 'Tolerance-based release plus a weekly 5% sample audit.',
    result: '',
  },
  {
    id: 'ini-agent', title: 'Agent change package: case summarization assist', opportunityId: 'opp-summary',
    processId: 'p-triage', processName: 'Customer case triage', site: 'Manila', method: 'kaizen',
    owner: 'Customer Care CI', stage: 'check', due: due(14), savingsHours: 780, savingsStage: 'estimated',
    validatedBy: '', waste: 'unusedTalent',
    evidence: '', background: '18 minutes per case is spent re-reading case history.',
    target: 'A draft summary in under 2 minutes, reviewed by the resolver.',
    countermeasure: 'A reviewed agent draft, a human approval step, and a no-auto-send rule.',
    result: '',
  },
  {
    id: 'ini-credit', title: 'Standard work: credit-hold decision record', opportunityId: 'opp-credit',
    processId: 'p-order', processName: 'Order intake & validation', site: 'Bensheim', method: 'standardWork',
    owner: 'Credit Manager', stage: 'do', due: due(27), savingsHours: 130, savingsStage: 'committed',
    validatedBy: '', waste: 'overProcessing',
    evidence: '', background: 'Four reviewers apply four thresholds and record no rationale.',
    target: 'One threshold table, a mandatory rationale field, no automation.',
    countermeasure: 'A one-page standard and a monthly review of 10 decisions.',
    result: '',
  },
  {
    id: 'ini-5s', title: '5S: order desk workspace and status lookups', opportunityId: 'opp-paper',
    processId: 'p-order', processName: 'Order intake & validation', site: 'Bensheim', method: '5s',
    owner: 'Order Desk Lead', stage: 'plan', due: due(38), savingsHours: 240, savingsStage: 'estimated',
    validatedBy: '', waste: 'contextSwitching',
    evidence: '', background: 'Three systems and one spreadsheet hold order status.',
    target: 'One status view, two clicks maximum, no spreadsheet.',
    countermeasure: 'A single status tile backed by SAP, and a printed 5S standard at the desk.',
    result: '',
  },
  {
    id: 'ini-rpa', title: 'RPA pilot: order intake bot', opportunityId: 'opp-exception',
    processId: 'p-order', processName: 'Order intake & validation', site: 'Bensheim', method: 'kaizen',
    owner: 'Automation CoE', stage: 'do', due: due(45), savingsHours: 430, savingsStage: 'committed',
    validatedBy: '', waste: 'handoffs',
    evidence: '', background: 'A pilot bot re-keys portal orders into SAP.',
    target: '430 hours a year from the re-key path.',
    countermeasure: 'Bot built before the path was standardized.',
    result: '',
  },
]

export const LINES = INITIATIVES.map(initiativeLine)

// MARK: - Meetings

export const MEETINGS: Meeting[] = [
  {
    id: 'meet-huddle', title: 'Daily huddle · Customer Care', kind: 'dailyHuddle',
    date: iso(0), durationMinutes: 15, site: 'Manila', owner: 'Customer Care Lead',
    attendees: ['Customer Care Lead', 'Triage Agent', 'Resolver'],
    processId: 'p-triage', initiativeId: '', status: 'notes',
    summary: 'Backlog above target; add the queue to the daily board.',
    recurring: true, cadence: 'Daily 08:30', kgId: 'kg-meeting-meet-huddle',
  },
  {
    id: 'meet-kaizen', title: 'Kaizen · pricing check in order intake', kind: 'kaizen',
    date: iso(3), durationMinutes: 480, site: 'Bensheim', owner: 'Ops Excellence Lead',
    attendees: ['Order Desk Lead', 'Pricing Analyst', 'Credit Manager', 'Ops Excellence Lead'],
    processId: 'p-order', initiativeId: 'ini-pricing', status: 'notes',
    summary: 'Remove the second pricing check above tolerance and audit by sample.',
    recurring: false, cadence: '', kgId: 'kg-meeting-meet-kaizen',
  },
  {
    id: 'meet-a3', title: 'A3 review · invoice exception codes', kind: 'a3Review',
    date: iso(6), durationMinutes: 45, site: 'Wrocław', owner: 'AP Team Lead',
    attendees: ['AP Team Lead', 'Buyer', 'CI Manager'],
    processId: 'p-invoice', initiativeId: 'ini-codes', status: 'done',
    summary: 'Rework 34% to 11%; adopt the single code list and close.',
    recurring: false, cadence: '', kgId: 'kg-meeting-meet-a3',
  },
  {
    id: 'meet-leadership', title: 'Leadership review · Q4 pipeline', kind: 'leadership',
    date: iso(2), durationMinutes: 60, site: '', owner: 'CI Manager',
    attendees: ['CI Manager', 'Finance Business Partner', 'Site CI Leads'],
    processId: '', initiativeId: '', status: 'done',
    summary: 'Fund the agent change package subject to security review.',
    recurring: true, cadence: 'Monthly', kgId: 'kg-meeting-meet-leadership',
  },
]

const block = (meetingId: string, order: number, kind: BlockKind, text: string,
               extra: Partial<MeetingBlock> = {}): MeetingBlock => ({
  id: `blk-${meetingId}-${order}`, meetingId, order, kind, text,
  checked: false, owner: '', ...extra,
})

export const BLOCKS: MeetingBlock[] = [
  block('meet-huddle', 0, 'heading', 'Yesterday'),
  block('meet-huddle', 1, 'bullet', 'Backlog peaked at 84 cases; six SLA breaches.'),
  block('meet-huddle', 2, 'heading', 'Today'),
  block('meet-huddle', 3, 'bullet', 'Clear the 12 oldest cases first.'),
  block('meet-huddle', 4, 'decision', 'Add the triage backlog to the daily management board, reviewed at 08:30.'),
  block('meet-huddle', 5, 'action', 'Create the daily board and review it for two weeks.',
    { owner: 'Customer Care Lead', due: iso(-14) }),
  block('meet-huddle', 6, 'action', 'Ask IT for a ServiceNow queue export at 07:00.',
    { owner: 'Triage Agent', due: iso(-7) }),
  block('meet-huddle', 7, 'callout', 'No individual volumes are discussed in the huddle; only the queue.'),

  block('meet-kaizen', 0, 'heading', 'Problem'),
  block('meet-kaizen', 1, 'text', 'Two pricing checks disagree on 18% of orders and re-open them.'),
  block('meet-kaizen', 2, 'heading', 'Target'),
  block('meet-kaizen', 3, 'text', 'Remove the SAP re-check above the €5k tolerance; keep a 5% sample audit.'),
  block('meet-kaizen', 4, 'decision', 'Drop the SAP re-check above the €5k tolerance from Monday.'),
  block('meet-kaizen', 5, 'action', 'Update SOP O2C-04 to v6.3 and brief the desk.',
    { owner: 'Order Desk Lead', due: iso(-10) }),
  block('meet-kaizen', 6, 'action', 'Quantify rework before and after against KYP.ai.',
    { owner: 'Ops Excellence Lead', due: iso(-42), linkedKind: 'opportunity', linkedId: 'opp-pricing' }),

  block('meet-a3', 0, 'heading', 'Result'),
  block('meet-a3', 1, 'text', 'Rework 34% → 11% over six weeks; 540 hours confirmed.'),
  block('meet-a3', 2, 'decision', 'Adopt the single code list across both AP teams.'),
  block('meet-a3', 3, 'action', 'Share the list with the Manila AP team.',
    { owner: 'AP Team Lead', due: iso(-7) }),

  block('meet-leadership', 0, 'heading', 'Portfolio'),
  block('meet-leadership', 1, 'bullet', 'Validated 540 h; committed 840 h; estimated 1,020 h.'),
  block('meet-leadership', 2, 'decision', 'Fund the case-summarization agent change package, subject to security review.'),
  block('meet-leadership', 3, 'action', 'Request the security review for the agent change package.',
    { owner: 'Customer Care CI', due: iso(-5), linkedKind: 'opportunity', linkedId: 'opp-summary' }),
  block('meet-leadership', 4, 'action', 'Resolve the order-intake double count before the roll-up.',
    { owner: 'Ops Excellence Lead', due: iso(-9) }),
]

// Knowledge graph, generated from the same facts.
const nodes: KGNode[] = []
const edges: KGEdge[] = []
const addNode = (node: KGNode) => nodes.push(node)
const addEdge = (from: string, predicate: KGEdge['predicate'], to: string, confidence = 0.9) =>
  edges.push({ from, predicate, to, confidence })

const sites = [...new Set(PROCESSES.map(p => p.site))]
const appId = (name: string) => `kg-app-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
const apps = [...new Set(PROCESSES.flatMap(p => p.applications))]
const roles = [...new Set(PROCESSES.flatMap(p => p.steps.map(s => s.role)))]

for (const site of sites) {
  addNode({ id: `kg-site-${site.toLowerCase().replace(/\s+/g, '-')}`, kind: 'site', name: site, confidence: 0.98, review: 'confirmed', source: 'Flightdeck registry', sourceId: `registry-site-${site}`, validFrom: iso(120) })
}
for (const app of apps) {
  addNode({ id: appId(app), kind: 'application', name: app, confidence: 0.93, review: 'confirmed', source: 'KYP.ai application usage', sourceId: `kyp-app-${app}`, validFrom: iso(120) })
}
for (const role of roles) {
  addNode({ id: `kg-role-${role.toLowerCase().replace(/\s+/g, '-')}`, kind: 'role', name: role, confidence: 0.9, review: 'confirmed', source: 'KYP.ai role aggregation', sourceId: `kyp-role-${role}`, validFrom: iso(120) })
}
addNode({ id: 'kg-hoshin-o2c', kind: 'hoshinObjective', name: 'Cut order-to-cash lead time by 25%', confidence: 0.95, review: 'confirmed', source: 'Hoshin deployment 2026', sourceId: 'hoshin-o2c', validFrom: iso(120) })
addNode({ id: 'kg-hoshin-rework', kind: 'hoshinObjective', name: 'Halve administrative rework in finance', confidence: 0.95, review: 'confirmed', source: 'Hoshin deployment 2026', sourceId: 'hoshin-rework', validFrom: iso(120) })

for (const process of PROCESSES) {
  addNode({ id: process.kgId, kind: 'process', name: process.name, confidence: process.confidence, review: 'confirmed', source: 'KYP.ai task mining', sourceId: process.kypId, validFrom: iso(120), processId: process.id })
  addEdge(process.kgId, 'performedIn', `kg-site-${process.site.toLowerCase().replace(/\s+/g, '-')}`, 0.99)
  addEdge(process.kgId, 'ownedBy', `kg-role-${process.owner.toLowerCase().replace(/\s+/g, '-')}`, 0.85)
  for (const app of process.applications) {
    addEdge(process.kgId, 'uses', appId(app), 0.9)
  }
  process.steps.forEach((step, index) => {
    addNode({ id: step.kgId, kind: 'step', name: step.name, confidence: 0.87, review: 'confirmed', source: 'KYP.ai task mining', sourceId: `kyp-${step.id}`, validFrom: iso(120) })
    const next = process.steps[index + 1]
    if (next) addEdge(step.kgId, 'handsOffTo', next.kgId, 0.88)
  })
}

for (const opportunity of OPPORTUNITIES) {
  addNode({ id: opportunity.kgId, kind: 'opportunity', name: opportunity.title, confidence: Math.min(0.95, opportunity.confidence + 0.02), review: 'confirmed', source: 'ProcessLink opportunity engine', sourceId: opportunity.id, validFrom: iso(20) })
  addEdge(`kg-proc-${opportunity.processId}`, 'hasOpportunity', opportunity.kgId, 0.9)
}
for (const initiative of INITIATIVES) {
  addNode({ id: `kg-ini-${initiative.id}`, kind: 'initiative', name: initiative.title, confidence: 0.93, review: 'confirmed', source: 'ProcessLink TEOA layer', sourceId: initiative.id, validFrom: iso(30) })
  addNode({ id: `kg-savings-${initiative.id}`, kind: 'savingsRecord', name: `${Math.round(initiative.savingsHours)} h · ${initiative.savingsStage}`, confidence: 0.9, review: 'confirmed', source: 'ProcessLink value tracking', sourceId: initiative.id, validFrom: iso(30) })
  addEdge(`kg-opp-${initiative.opportunityId}`, 'addressedBy', `kg-ini-${initiative.id}`, 0.9)
  addEdge(`kg-ini-${initiative.id}`, 'realizesSavings', `kg-savings-${initiative.id}`, 0.9)
}
addNode({ id: 'kg-app-sap-ecc', kind: 'application', name: 'SAP ECC', confidence: 0.61, review: 'suggested', source: 'KYP.ai application usage', sourceId: 'kyp-app-ecc', validFrom: iso(120), note: 'Entity resolution found a likely duplicate. A human must confirm or reject the merge.' })
addEdge('kg-app-sap-ecc', 'variantOf', appId('SAP S/4HANA'), 0.61)
addNode({ id: 'kg-team-sales-support', kind: 'role', name: 'Sales Support', confidence: 0.72, review: 'suggested', source: 'KYP.ai role aggregation', sourceId: 'kyp-team-sales-support', validFrom: iso(120), note: 'Entity resolution found a likely duplicate. A human must confirm or reject the merge.' })
addEdge('kg-team-sales-support', 'variantOf', 'kg-role-order-desk', 0.72)

// Meetings, decisions and actions are graph facts too.
for (const meeting of MEETINGS) {
  addNode({ id: meeting.kgId, kind: 'meeting', name: meeting.title, confidence: 0.9,
    review: 'confirmed', source: 'ProcessLink meeting notes', sourceId: meeting.id,
    validFrom: meeting.date, processId: meeting.processId || undefined })
  if (meeting.processId) addEdge(`kg-proc-${meeting.processId}`, 'discussedIn', meeting.kgId, 0.85)
  if (meeting.initiativeId) addEdge(`kg-ini-${meeting.initiativeId}`, 'discussedIn', meeting.kgId, 0.85)
}
for (const item of BLOCKS) {
  if (item.kind !== 'decision' && item.kind !== 'action') continue
  const kind = item.kind
  addNode({ id: `kg-${kind}-${item.id}`, kind, name: item.text.slice(0, 90),
    confidence: 0.9, review: 'confirmed', source: 'ProcessLink meeting notes',
    sourceId: item.id, validFrom: MEETINGS.find(m => m.id === item.meetingId)?.date ?? iso(30) })
  addEdge(`kg-${kind}-${item.id}`, 'documentedIn', `kg-meeting-${item.meetingId}`, 0.95)
  if (item.owner) {
    const roleId = `kg-role-${item.owner.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
    if (!nodes.some(n => n.id === roleId)) {
      addNode({ id: roleId, kind: 'role', name: item.owner, confidence: 0.88,
        review: 'confirmed', source: 'Meeting action owner', sourceId: item.id, validFrom: iso(30) })
    }
    addEdge(`kg-${kind}-${item.id}`, 'assignedTo', roleId, 0.9)
  }
}

export const KG_NODES = nodes
export const KG_EDGES = edges

export const GOVERNANCE: GovernanceItem[] = [
  { id: 'gov-dpia', title: 'Data protection impact assessment', detail: 'Completed for the pilot in DE and PL; PH and MX are in review.', group: 'Data protection', status: 'inProgress', owner: 'Data Protection Office' },
  { id: 'gov-legal', title: 'Legal review per country', detail: 'DE and PL approved for process improvement only. PH and MX pending.', group: 'Data protection', status: 'inProgress', owner: 'Legal' },
  { id: 'gov-dpia-prod', title: 'DPIA for production rollout', detail: 'The pilot DPIA is not a production DPIA.', group: 'Data protection', status: 'notStarted', owner: 'Data Protection Office' },
  { id: 'gov-wc', title: 'Works council consultation (DE)', detail: 'The Bensheim works council has the draft agreement. No capture expansion before sign-off.', group: 'People', status: 'blocked', owner: 'HR Business Partner' },
  { id: 'gov-notice', title: 'Employee transparency notice', detail: 'Published in the intranet and linked from the capture page.', group: 'People', status: 'done', owner: 'Internal Communications' },
  { id: 'gov-scope', title: 'Capture scope confirmed', detail: 'Bensheim, Wrocław, Manila, Guadalajara. No personal devices.', group: 'People', status: 'done', owner: 'KYP.ai Administrator' },
  { id: 'gov-owner', title: 'Named data owner', detail: 'CI Manager (role) is accountable for every use of KYP.ai data.', group: 'Accountability', status: 'done', owner: 'CI Manager' },
  { id: 'gov-retention', title: 'Retention schedule', detail: 'Aggregates 400 days; raw capture stays in KYP.ai.', group: 'Accountability', status: 'done', owner: 'Data Owner' },
  { id: 'gov-ai', title: 'AI provider and region approval', detail: 'Local approved. Hosted provider approved for EU processing only.', group: 'AI & security', status: 'inProgress', owner: 'Security' },
]

export const AUDIT: AuditEntry[] = [
  { id: 'a1', at: iso(12), actor: 'CI Manager (role)', action: 'governance.reviewed', subject: 'Launch checklist', detail: 'DPIA reviewed with the Data Protection Office.' },
  { id: 'a2', at: iso(3), actor: 'CI Manager (role)', action: 'sync.completed', subject: 'KYP.ai sandbox', detail: '312 objects fetched, 4 skipped by policy.' },
  { id: 'a3', at: iso(9), actor: 'CI Manager (role)', action: 'initiative.created', subject: 'Kaizen: cut the second pricing check', detail: 'From opportunity opp-pricing.' },
  { id: 'a4', at: iso(6), actor: 'CI Manager (role)', action: 'savings.validated', subject: 'A3: one exception-code list', detail: '540 h validated by CI Manager, Wrocław.' },
  { id: 'a5', at: iso(2), actor: 'CI Manager (role)', action: 'ai.answer', subject: 'Ask the process', detail: 'Question answered locally with 6 citations.' },
]
