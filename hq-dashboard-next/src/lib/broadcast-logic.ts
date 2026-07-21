import { supabase } from './supabase';

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
    
    if (role === 'HQ_OFFICER' || role === 'HQ_COMMAND' || badgeId.startsWith('HQ-')) return 'hq_command';
    if (role === 'LGA_OFFICER' || role === 'LGA_COMMAND' || badgeId.startsWith('LGA-')) return 'lga_command';
    if (role === 'WARD_OFFICER' || role === 'WARD_COMMAND' || badgeId.startsWith('WD-')) return 'ward_command';
    if (role === 'POLLING_UNIT_OFFICER' || role === 'POLLING_OFFICER' || role === 'UNIT_COMMAND' || badgeId.startsWith('PU-')) return 'unit_command';
    
    if (data.badgeId) return 'field_agents';
    return 'citizens';
}

export async function getCleanBroadcastList() {
  const { data } = await supabase.from('profiles').select('*');
  return data || [];
}
