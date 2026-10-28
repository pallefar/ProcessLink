/**
 * Flightdeck sub-app manifest for ProcessLink.
 *
 * Drop-in shape copied from `flightdeck/server/subapps/advantage/manifest.ts`
 * (the host's `SubAppManifest` type is not imported here: this package builds
 * outside the Flightdeck repo, and a cross-repo type import would make the
 * standalone build depend on the host's path layout).
 */
export interface ProcessLinkManifest {
  id: 'processlink'
  label: string
  version: string
  minHostVersion: string
  icon: string
  navSection: string
  routePrefix: string
  webModuleId: string
  capabilities: string[]
  navPath: string
}

export const processLinkManifest: ProcessLinkManifest = {
  id: 'processlink',
  // The practice layer keeps the TEOA name visible; the product name is
  // ProcessLink. Same convention as "TEOA · Operational Advantage".
  label: 'ProcessLink · TEOA',
  version: '0.1.0',
  minHostVersion: '5.0.0',
  icon: '🔗',
  navSection: 'Ops & insight',
  routePrefix: '/api/apps/processlink',
  webModuleId: 'processlink',
  capabilities: [],
  navPath: '/console/apps/processlink',
}

/** Off by default, like every other sub-app in the host. */
export const KILL_SWITCH_ENV = 'SUBAPP_PROCESSLINK_ENABLED'
