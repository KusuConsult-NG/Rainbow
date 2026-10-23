import { supabase } from './supabase';
import { tierForRole } from './command-roles';

export type UserSegment = 
  | 'hq_command'
  | 'lga_command'
  | 'ward_command'
  | 'unit_command'
  | 'field_agents'
  | 'citizens';

export function categorizeUser(data: any): UserSegment {
    const role = data.role?.toUpperCase();
    const badgeId = data.badgeId?.toUpperCase() || '';
    
    // THE ROLE DECIDES THE RUNG; THE BADGE PREFIX IS THE FALLBACK.
    //
    // These were twelve literal comparisons and a STATE_COMMANDER matched none
    // of them, so an HQ duty officer with a badge fell through to
    // 'field_agents' and an advisory addressed to hq_command missed them
    // entirely. The rung now comes from the role-to-rung map, with the badge
    // prefix kept for an account whose role is blank. T-97.
    const tier = tierForRole(role);
    if (tier === 'HQ' || badgeId.startsWith('HQ-')) return 'hq_command';
    if (tier === 'LGA' || badgeId.startsWith('LGA-')) return 'lga_command';
    if (tier === 'WARD' || badgeId.startsWith('WD-')) return 'ward_command';
    if (tier === 'UNIT' || badgeId.startsWith('PU-')) return 'unit_command';
    
    if (data.badgeId) return 'field_agents';
    return 'citizens';
}

export async function getCleanBroadcastList() {
  const { data } = await supabase.from('profiles').select('*');
  return data || [];
}
