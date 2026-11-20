// SPDX-License-Identifier: AGPL-3.0-or-later

import type {ElectronAPI} from '@app/types/electron.d';

export function isElectron(): boolean {
	if (typeof window === 'undefined') return false;
	return (
		(
			window as {
				electron?: ElectronAPI;
			}
		).electron !== undefined
	);
}

// Electron's default user agent carries the app name with its spaces removed,
// so Fluxer Desktop's says Fluxer/, FluxerCanary/ or FluxerDevelopment/.
// Other Electron apps that embed the web app, such as a preview pane, have
// no desktop bridge either and must not count as a broken installation.
const FLUXER_DESKTOP_USER_AGENT = /\bFluxer(?:Canary|Development)?\/\S/;
const ELECTRON_USER_AGENT = /\bElectron\/\d+(?:\.\d+)*/;

export function hasUnavailableElectronNativeContext(): boolean {
	if (typeof window === 'undefined' || typeof navigator === 'undefined') return false;
	return (
		(
			window as {
				electron?: ElectronAPI | null;
			}
		).electron == null &&
		ELECTRON_USER_AGENT.test(navigator.userAgent) &&
		FLUXER_DESKTOP_USER_AGENT.test(navigator.userAgent)
	);
}
