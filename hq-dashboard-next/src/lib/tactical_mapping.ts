// Canonical Tactical Mapping for Plateau State (Complete 17 LGAs) - Web Version

export interface TacticalWard {
  id: string;
  name: string;
  pollingUnits: string[];
}

export interface TacticalJurisdiction {
  id: string;
  name: string;
  wards: TacticalWard[];
  siecWards?: TacticalWard[];
}

export const plateauTacticalMap: TacticalJurisdiction[] = [
  { id: 'LGA_BARKIN_LADI', name: 'Barkin Ladi', wards: [
    { id: 'WARD_HEIPANG', name: 'Heipang', pollingUnits: ['PU-BL-01', 'PU-BL-02'] },
    { id: 'WARD_ROPP', name: 'Ropp', pollingUnits: ['PU-BL-10', 'PU-BL-11'] },
  ], siecWards: []},
  { id: 'LGA_BASSA', name: 'Bassa', wards: [
    { id: 'WARD_MIANGO', name: 'Miango', pollingUnits: ['PU-BS-01', 'PU-BS-02'] },
    { id: 'WARD_KWALL', name: 'Kwall', pollingUnits: ['PU-BS-10'] },
  ], siecWards: []},
  { id: 'LGA_BOKKOS', name: 'Bokkos', wards: [
    { id: 'WARD_BOKKOS_CENTRAL', name: 'Bokkos Central', pollingUnits: ['PU-BK-01'] },
    { id: 'WARD_DAFFO', name: 'Daffo', pollingUnits: ['PU-BK-10'] },
  ], siecWards: []},
  { id: 'LGA_JOS_EAST', name: 'Jos East', wards: [
    { id: 'WARD_FEDERE', name: 'Federe', pollingUnits: ['PU-JE-01'] },
    { id: 'WARD_FOBUR', name: 'Fobur', pollingUnits: ['PU-JE-10'] },
  ], siecWards: []},
  { id: 'LGA_JOS_NORTH', name: 'Jos North', wards: [
    { id: 'WARD_TUDUN_WADA', name: 'Tudun Wada', pollingUnits: ['PU-JN-01', 'PU-JN-02', 'PU-JN-03'] },
    { id: 'WARD_NARAGUTA', name: 'Naraguta', pollingUnits: ['PU-JN-10', 'PU-JN-11'] },
    { id: 'WARD_GANGARE', name: 'Gangare', pollingUnits: ['PU-JN-20'] },
  ], siecWards: []},
  { id: 'LGA_JOS_SOUTH', name: 'Jos South', wards: [
    { id: 'WARD_BUKURU', name: 'Bukuru', pollingUnits: ['PU-JS-01', 'PU-JS-02'] },
    { id: 'WARD_DU', name: 'Du', pollingUnits: ['PU-JS-10'] },
    { id: 'WARD_GYEL', name: 'Gyel', pollingUnits: ['PU-JS-20'] },
  ], siecWards: []},
  { id: 'LGA_KANAM', name: 'Kanam', wards: [
    { id: 'WARD_DENGI', name: 'Dengi', pollingUnits: ['PU-KN-01'] },
    { id: 'WARD_GARGA', name: 'Garga', pollingUnits: ['PU-KN-10'] },
  ], siecWards: []},
  { id: 'LGA_KANKE', name: 'Kanke', wards: [
    { id: 'WARD_KABWIR', name: 'Kabwir', pollingUnits: ['PU-KK-01'] },
  ], siecWards: []},
  { id: 'LGA_LANGTANG_NORTH', name: 'Langtang North', wards: [
    { id: 'WARD_LANGTANG_CENTRAL', name: 'Langtang Central', pollingUnits: ['PU-LN-01'] },
  ], siecWards: []},
  { id: 'LGA_LANGTANG_SOUTH', name: 'Langtang South', wards: [
    { id: 'WARD_MABUDI', name: 'Mabudi', pollingUnits: ['PU-LS-01'] },
  ], siecWards: []},
  { id: 'LGA_MANGU', name: 'Mangu', wards: [
    { id: 'WARD_MANGU_HALLE', name: 'Mangu Halle', pollingUnits: ['PU-MG-01'] },
    { id: 'WARD_GINDIRI', name: 'Gindiri', pollingUnits: ['PU-MG-10'] },
  ], siecWards: []},
  { id: 'LGA_MIKANG', name: 'Mikang', wards: [
    { id: 'WARD_TUNKUS', name: 'Tunkus', pollingUnits: ['PU-MK-01'] },
  ], siecWards: []},
  { id: 'LGA_PANKSHIN', name: 'Pankshin', wards: [
    { id: 'WARD_PANKSHIN_CENTRAL', name: 'Pankshin Central', pollingUnits: ['PU-PK-01'] },
  ], siecWards: []},
  { id: 'LGA_QUAN_PAN', name: 'Qua\'an Pan', wards: [
    { id: 'WARD_BAAP', name: 'Ba\'ap', pollingUnits: ['PU-QP-01'] },
    { id: 'WARD_DOEMAK', name: 'Doemak', pollingUnits: ['PU-QP-10'] },
  ], siecWards: []},
  { id: 'LGA_RIYOM', name: 'Riyom', wards: [
    { id: 'WARD_RIYOM_CENTRAL', name: 'Riyom Central', pollingUnits: ['PU-RY-01'] },
  ], siecWards: []},
  { id: 'LGA_SHENDAM', name: 'Shendam', wards: [
    { id: 'WARD_SHENDAM_CENTRAL', name: 'Shendam Central', pollingUnits: ['PU-SD-01'] },
  ], siecWards: []},
  { id: 'LGA_WASE', name: 'Wase', wards: [
    { id: 'WARD_WASE_CENTRAL', name: 'Wase Central', pollingUnits: ['PU-WS-01'] },
    { id: 'WARD_BASHAR', name: 'Bashar', pollingUnits: ['PU-WS-10'] },
  ], siecWards: []},
];
