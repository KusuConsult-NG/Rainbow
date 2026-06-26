import { db } from './firebase';
import { collection, query, where, getDocs, limit, orderBy } from 'firebase/firestore';

/**
 * Operation Rainbow — High-Precision Audience Segmenting
 * 
 * Centralised logic for categorising users into mutually exclusive segments.
 * Focuses on jurisdictional hierarchy and staff vs citizen roles.
 */

export type UserSegment = 
  | 'hq_command'    // HQ Officers
  | 'lga_command'   // LGA Commanders
  | 'ward_command'  // Ward Commanders
  | 'unit_command'  // Unit Commanders
  | 'field_agents'  // Responders without command role
  | 'citizens';      // General public

/**
 * Categorises a user based on their role and jurisdictional markers.
 */
export function categorizeUser(data: any): UserSegment {
    const role = data.role?.toUpperCase();
    const badgeId = data.badgeId?.toUpperCase() || '';
    
    if (role === 'HQ_OFFICER' || role === 'HQ_COMMAND' || badgeId.startsWith('HQ-')) return 'hq_command';
    
    if (role === 'LGA_OFFICER' || role === 'LGA_COMMAND' || badgeId.startsWith('LGA-')) return 'lga_command';
    
    if (role === 'WARD_OFFICER' || role === 'WARD_COMMAND' || badgeId.startsWith('WD-')) return 'ward_command';
    
    if (role === 'POLLING_UNIT_OFFICER' || role === 'POLLING_OFFICER' || role === 'UNIT_COMMAND' || badgeId.startsWith('PU-')) return 'unit_command';
    
    // Check if they have a badgeId but no command role prefix match
    if (data.badgeId) return 'field_agents';
    
    return 'citizens';
}

export interface BroadcastFilters {
    audience: UserSegment | 'all';
    lga?: string;
    ward?: string;
    pu?: string;
}

/**
 * Generates a clean list of recipients based on Rainbow's tactical hierarchy.
 * Note: Uses client-side Firebase logic as this is intended for the HQ Dashboard.
 */
export async function getCleanBroadcastList(filters?: BroadcastFilters) {
    try {
        console.log(`[RainbowBroadcast] Segmenting audience: ${filters?.audience || 'all'}...`);

        let q = query(collection(db, 'users'));

        // Apply filters if possible via query
        if (filters?.audience && filters.audience !== 'all') {
            const roleMap: Record<string, string[]> = {
                hq_command: ['HQ_OFFICER', 'HQ_COMMAND'],
                lga_command: ['LGA_OFFICER', 'LGA_COMMAND'],
                ward_command: ['WARD_OFFICER', 'WARD_COMMAND'],
                unit_command: ['POLLING_OFFICER', 'UNIT_COMMAND', 'POLLING_UNIT_OFFICER']
            };
            
            if (roleMap[filters.audience]) {
                q = query(q, where('role', 'in', roleMap[filters.audience]));
            }
        }

        const snapshot = await getDocs(q);
        const recipients: any[] = [];

        snapshot.docs.forEach(doc => {
            const data = doc.data();
            const segment = categorizeUser(data);

            // Filter by audience if not done in query (for field_agents/citizens)
            if (filters?.audience && filters.audience !== 'all' && filters.audience !== segment) {
                return;
            }

            // Jurisdictional Filters
            if (filters?.lga && data.geo_lga !== filters.lga && data.lga !== filters.lga) return;
            if (filters?.ward && data.geo_ward !== filters.ward && data.ward !== filters.ward) return;
            if (filters?.pu && data.geo_pu !== filters.pu && data.pu !== filters.pu) return;

            recipients.push({
                uid: doc.id,
                name: data.displayName || data.fullName || 'User',
                phone: data.phone,
                email: data.email,
                role: data.role,
                segment
            });
        });

        return {
            success: true,
            data: {
                recipients,
                count: recipients.length
            }
        };

    } catch (error) {
        console.error('[RainbowBroadcast] Failed to generate list:', error);
        return { success: false, error: 'Failed to segment audience.' };
    }
}
