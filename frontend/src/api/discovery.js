/**
 * API Client for Service Discovery
 * Handles communication with the backend discovery endpoints
 */

/**
 * @typedef {Object} InstanceStats
 * @property {number} total - Total number of discovered instances
 * @property {number} ready - Number of ready instances
 * @property {number} notReady - Number of not-ready (booting/error) instances
 */

/**
 * @typedef {Object} DiscoveryStatus
 * @property {string} mode - Discovery mode (kubernetes-endpoints, kubernetes-pods, static)
 * @property {string} serviceName - Kubernetes service name being watched
 * @property {string|null} lastUpdate - ISO timestamp of last update
 * @property {InstanceStats} stats - Instance statistics
 * @property {Array} instances - List of discovered instances
 */

/**
 * Fetch live discovery status and instances
 * @returns {Promise<DiscoveryStatus>}
 */
export async function fetchLiveInstances() {
    try {
        const response = await fetch('/api/instances/live');
        if (!response.ok) {
            throw new Error(`Discovery API error: ${response.status}`);
        }
        return await response.json();
    } catch (error) {
        console.error('Failed to fetch live instances:', error);
        throw error;
    }
}

/**
 * Fetch discovery configuration info
 * @returns {Promise<Object>}
 */
export async function fetchDiscoveryInfo() {
    try {
        const response = await fetch('/api/instances/discovery-info');
        if (!response.ok) {
            throw new Error(`Discovery Info API error: ${response.status}`);
        }
        return await response.json();
    } catch (error) {
        console.error('Failed to fetch discovery info:', error);
        throw error;
    }
}

/**
 * Trigger a manual refresh of discovery
 * @returns {Promise<Object>}
 */
export async function refreshDiscovery() {
    try {
        const response = await fetch('/api/instances/refresh', {
            method: 'POST'
        });
        if (!response.ok) {
            throw new Error(`Refresh API error: ${response.status}`);
        }
        return await response.json();
    } catch (error) {
        console.error('Failed to refresh discovery:', error);
        throw error;
    }
}
