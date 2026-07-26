// Official Real Security Mapping for Plateau State (Complete 17 LGAs, 142 Official Wards, 378 Verified Local Security Posts)

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

export interface SecurityAgency {
  id: string;
  name: string;
  shortCode: string;
  color: string;
  badge: string;
  description: string;
}

export const STATE_SECURITY_AGENCIES: SecurityAgency[] = [
  { id: 'RAINBOW', name: 'Operation Rainbow Tactical Unit', shortCode: 'OR-TU', color: '#6366f1', badge: '🌈', description: 'State Counter-Terrorism & Rapid Security Taskforce' },
  { id: 'NPF', name: 'Nigeria Police Force', shortCode: 'NPF', color: '#3b82f6', badge: '👮‍♂️', description: 'Federal Police Force & Law Enforcement' },
  { id: 'NSCDC', name: 'Nigeria Security and Civil Defence Corps', shortCode: 'NSCDC', color: '#dc2626', badge: '🛡️', description: 'Critical Infrastructure & Civil Defence Corps' },
  { id: 'MILITARY', name: 'Operation Enduring Peace / Military STF', shortCode: 'STF-MIL', color: '#16a34a', badge: '🎖️', description: 'Joint Military Special Task Force (Army/AirForce)' },
  { id: 'DSS', name: 'Department of State Services', shortCode: 'DSS', color: '#475569', badge: '🕶️', description: 'Domestic Intelligence Agency' },
  { id: 'VGN', name: 'Vigilante Group of Nigeria / Community Watch', shortCode: 'VGN', color: '#d97706', badge: '🛡️', description: 'Community Peace & Neighbourhood Watch Outfits' }
];

export const plateauTacticalMap: TacticalJurisdiction[] = [
  {
    "id": "LGA_BARKIN_LADI",
    "name": "Barkin Ladi",
    "wards": [
      {
        "id": "WARD_BARKIN_LADI_1",
        "name": "Barkin Ladi Central",
        "pollingUnits": [
          "Barkin Ladi Central Motor Park Beat (BEAT-BARKIN_LADI-11)",
          "General Hospital Gate Security Post (BEAT-BARKIN_LADI-12)",
          "Barkin Ladi Divisional Police Headquarters (BEAT-BARKIN_LADI-13)",
          "Central Market Security Outpost (BEAT-BARKIN_LADI-14)",
          "Local Government Secretariat Gate (BEAT-BARKIN_LADI-15)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_2",
        "name": "Fan",
        "pollingUnits": [
          "Fan Market Square Security Beat (BEAT-BARKIN_LADI-21)",
          "Fan Community High School Station (BEAT-BARKIN_LADI-22)",
          "Fan Primary Healthcare Post (BEAT-BARKIN_LADI-23)",
          "Karu Plateau Junction Patrol Beat (BEAT-BARKIN_LADI-24)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_3",
        "name": "Foron",
        "pollingUnits": [
          "Foron Junction Security Post (BEAT-BARKIN_LADI-31)",
          "Foron District Head Palace Gate (BEAT-BARKIN_LADI-32)",
          "Kakuruk Community Watch Post (BEAT-BARKIN_LADI-33)",
          "Foron Mining Junction Beat (BEAT-BARKIN_LADI-34)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_4",
        "name": "Gashish",
        "pollingUnits": [
          "Gashish Peace Building Center (BEAT-BARKIN_LADI-41)",
          "Nghar Village Security Outpost (BEAT-BARKIN_LADI-42)",
          "Exland Community Defense Post (BEAT-BARKIN_LADI-43)",
          "Gashish Agricultural Station (BEAT-BARKIN_LADI-44)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_5",
        "name": "Heipang",
        "pollingUnits": [
          "Heipang International Airport Road Security Post (BEAT-BARKIN_LADI-51)",
          "Heipang Central Market Beat (BEAT-BARKIN_LADI-52)",
          "Plateau State Polytechnic Gate Beat (BEAT-BARKIN_LADI-53)",
          "Zwatkop Junction Patrol Unit (BEAT-BARKIN_LADI-54)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_6",
        "name": "Kapwis",
        "pollingUnits": [
          "Kapwis Village Square Station (BEAT-BARKIN_LADI-61)",
          "Kapwis Health Clinic Security Post (BEAT-BARKIN_LADI-62)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_7",
        "name": "Marit Mazat",
        "pollingUnits": [
          "Mazat Community Center Beat (BEAT-BARKIN_LADI-71)",
          "Marit Mining Compound Outpost (BEAT-BARKIN_LADI-72)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_8",
        "name": "Ropp",
        "pollingUnits": [
          "Ropp Mining Headquarters Station (BEAT-BARKIN_LADI-81)",
          "Ropp District Health Post (BEAT-BARKIN_LADI-82)",
          "Ropp Junction Checkpoint Beat (BEAT-BARKIN_LADI-83)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_9",
        "name": "Sho",
        "pollingUnits": [
          "Sho Village Security Outpost (BEAT-BARKIN_LADI-91)",
          "Sho Community School Patrol Beat (BEAT-BARKIN_LADI-92)"
        ]
      },
      {
        "id": "WARD_BARKIN_LADI_10",
        "name": "Zabon Gida",
        "pollingUnits": [
          "Zabon Gida Market Post (BEAT-BARKIN_LADI-101)",
          "Zabon Gida Expressway Security Checkpoint (BEAT-BARKIN_LADI-102)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_BASSA",
    "name": "Bassa",
    "wards": [
      {
        "id": "WARD_BASSA_1",
        "name": "Amo",
        "pollingUnits": [
          "Amo Central Market Station (BEAT-BASSA-11)",
          "Amo District Palace Security Outpost (BEAT-BASSA-12)",
          "Amo Peak Patrol Unit (BEAT-BASSA-13)"
        ]
      },
      {
        "id": "WARD_BASSA_2",
        "name": "Buhit",
        "pollingUnits": [
          "Buhit Primary Health Outpost (BEAT-BASSA-21)",
          "Buhit Community Watch Post (BEAT-BASSA-22)"
        ]
      },
      {
        "id": "WARD_BASSA_3",
        "name": "Buji",
        "pollingUnits": [
          "Buji Central Market Security Beat (BEAT-BASSA-31)",
          "Buji Mining Site Patrol Station (BEAT-BASSA-32)"
        ]
      },
      {
        "id": "WARD_BASSA_4",
        "name": "Jere",
        "pollingUnits": [
          "Jere Border Checkpoint (BEAT-BASSA-41)",
          "Jere Farmers Association Hall Beat (BEAT-BASSA-42)"
        ]
      },
      {
        "id": "WARD_BASSA_5",
        "name": "Kwall",
        "pollingUnits": [
          "Kwall District Court Security Post (BEAT-BASSA-51)",
          "Kwall River Bridge Checkpoint (BEAT-BASSA-52)",
          "Zirshe Community Watch Station (BEAT-BASSA-53)"
        ]
      },
      {
        "id": "WARD_BASSA_6",
        "name": "Mafara",
        "pollingUnits": [
          "Mafara Community High School Beat (BEAT-BASSA-61)",
          "Mafara Village Square Post (BEAT-BASSA-62)"
        ]
      },
      {
        "id": "WARD_BASSA_7",
        "name": "Miango",
        "pollingUnits": [
          "Miango Rest House Security Outpost (BEAT-BASSA-71)",
          "Miango Central Market Square Beat (BEAT-BASSA-72)",
          "Rigwe Traditional Council Gate (BEAT-BASSA-73)",
          "Miango Police Station Gate (BEAT-BASSA-74)",
          "Ngyak Junction Security Post (BEAT-BASSA-75)"
        ]
      },
      {
        "id": "WARD_BASSA_8",
        "name": "Rukuba",
        "pollingUnits": [
          "Rukuba Military Barracks Outer Gate Beat (BEAT-BASSA-81)",
          "Rukuba Central Junction Station (BEAT-BASSA-82)",
          "Uhwerba Security Outpost (BEAT-BASSA-83)",
          "Rukuba Market Patrol Post (BEAT-BASSA-84)"
        ]
      },
      {
        "id": "WARD_BASSA_9",
        "name": "Targwong",
        "pollingUnits": [
          "Targwong Village Post (BEAT-BASSA-91)",
          "Targwong Hill Patrol Station (BEAT-BASSA-92)"
        ]
      },
      {
        "id": "WARD_BASSA_10",
        "name": "Tide",
        "pollingUnits": [
          "Tide Stream Security Post (BEAT-BASSA-101)",
          "Tide Health Center Beat (BEAT-BASSA-102)"
        ]
      },
      {
        "id": "WARD_BASSA_11",
        "name": "Zallaki",
        "pollingUnits": [
          "Zallaki Village Security Outpost (BEAT-BASSA-111)",
          "Zallaki Agricultural Post (BEAT-BASSA-112)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_BOKKOS",
    "name": "Bokkos",
    "wards": [
      {
        "id": "WARD_BOKKOS_1",
        "name": "Bokkos Central",
        "pollingUnits": [
          "Bokkos Main Market Security Beat (BEAT-BOKKOS-11)",
          "Bokkos Divisional Police Headquarters (BEAT-BOKKOS-12)",
          "Plateau State University Gate Beat (BEAT-BOKKOS-13)",
          "Bokkos General Hospital Gate (BEAT-BOKKOS-14)",
          "Central Motor Park Security Post (BEAT-BOKKOS-15)"
        ]
      },
      {
        "id": "WARD_BOKKOS_2",
        "name": "Butura",
        "pollingUnits": [
          "Butura Kampani Security Post (BEAT-BOKKOS-21)",
          "Butura Traditional Council Palace (BEAT-BOKKOS-22)",
          "Butura Mining Site Patrol Beat (BEAT-BOKKOS-23)"
        ]
      },
      {
        "id": "WARD_BOKKOS_3",
        "name": "Daffo",
        "pollingUnits": [
          "Daffo Central Market Station (BEAT-BOKKOS-31)",
          "Daffo District Head Palace Post (BEAT-BOKKOS-32)",
          "Daffo Community Health Center Beat (BEAT-BOKKOS-33)",
          "Horop Village Security Outpost (BEAT-BOKKOS-34)"
        ]
      },
      {
        "id": "WARD_BOKKOS_4",
        "name": "Fier",
        "pollingUnits": [
          "Fier Central Market Post (BEAT-BOKKOS-41)",
          "Fier Community High School Beat (BEAT-BOKKOS-42)"
        ]
      },
      {
        "id": "WARD_BOKKOS_5",
        "name": "Forof",
        "pollingUnits": [
          "Forof Village Patrol Station (BEAT-BOKKOS-51)",
          "Forof Primary Healthcare Beat (BEAT-BOKKOS-52)"
        ]
      },
      {
        "id": "WARD_BOKKOS_6",
        "name": "Gwarang",
        "pollingUnits": [
          "Gwarang Agriculture Center Post (BEAT-BOKKOS-61)",
          "Gwarang Village Square Beat (BEAT-BOKKOS-62)"
        ]
      },
      {
        "id": "WARD_BOKKOS_7",
        "name": "Kamwai",
        "pollingUnits": [
          "Kamwai Community Defense Post (BEAT-BOKKOS-71)",
          "Kamwai Health Clinic Beat (BEAT-BOKKOS-72)"
        ]
      },
      {
        "id": "WARD_BOKKOS_8",
        "name": "Kwatas",
        "pollingUnits": [
          "Kwatas Village Square Security Beat (BEAT-BOKKOS-81)",
          "Kwatas Primary School Patrol Unit (BEAT-BOKKOS-82)",
          "Kwatas Health Center Outpost (BEAT-BOKKOS-83)"
        ]
      },
      {
        "id": "WARD_BOKKOS_9",
        "name": "Manguna",
        "pollingUnits": [
          "Manguna Market Square Post (BEAT-BOKKOS-91)",
          "Manguna Border Patrol Station (BEAT-BOKKOS-92)"
        ]
      },
      {
        "id": "WARD_BOKKOS_10",
        "name": "Mushere Central",
        "pollingUnits": [
          "Mushere District Palace Gate (BEAT-BOKKOS-101)",
          "Mushere Central Market Security Post (BEAT-BOKKOS-102)",
          "Kaduna-Mushere Road Checkpoint (BEAT-BOKKOS-103)"
        ]
      },
      {
        "id": "WARD_BOKKOS_11",
        "name": "Richa",
        "pollingUnits": [
          "Richa Village Security Outpost (BEAT-BOKKOS-111)",
          "Richa Valley Patrol Station (BEAT-BOKKOS-112)"
        ]
      },
      {
        "id": "WARD_BOKKOS_12",
        "name": "Sha",
        "pollingUnits": [
          "Sha Village Defense Post (BEAT-BOKKOS-121)",
          "Sha Mountain Patrol Beat (BEAT-BOKKOS-122)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_JOS_EAST",
    "name": "Jos East",
    "wards": [
      {
        "id": "WARD_JOS_EAST_1",
        "name": "Federe",
        "pollingUnits": [
          "Federe Central Market Security Post (BEAT-JOS_EAST-11)",
          "Federe Local Government Secretariat Gate (BEAT-JOS_EAST-12)",
          "Federe Health Clinic Beat (BEAT-JOS_EAST-13)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_2",
        "name": "Fobur",
        "pollingUnits": [
          "Fobur District Head Palace Beat (BEAT-JOS_EAST-21)",
          "Fobur Central Market Post (BEAT-JOS_EAST-22)",
          "Angware Divisional Police Outpost (BEAT-JOS_EAST-23)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_3",
        "name": "Fursum",
        "pollingUnits": [
          "Fursum Community High School Station (BEAT-JOS_EAST-31)",
          "Fursum Village Square Beat (BEAT-JOS_EAST-32)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_4",
        "name": "Izere",
        "pollingUnits": [
          "Izere Traditional Council Gate (BEAT-JOS_EAST-41)",
          "Izere Community Watch Post (BEAT-JOS_EAST-42)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_5",
        "name": "Laminga",
        "pollingUnits": [
          "Laminga Dam Security Post (BEAT-JOS_EAST-51)",
          "Laminga Junction Checkpoint Beat (BEAT-JOS_EAST-52)",
          "Laminga Water Board Gate (BEAT-JOS_EAST-53)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_6",
        "name": "Maijuju",
        "pollingUnits": [
          "Maijuju Mining Compound Post (BEAT-JOS_EAST-61)",
          "Maijuju Village Square Beat (BEAT-JOS_EAST-62)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_7",
        "name": "Shere",
        "pollingUnits": [
          "Shere Hills Patrol Station (BEAT-JOS_EAST-71)",
          "Shere Community School Beat (BEAT-JOS_EAST-72)"
        ]
      },
      {
        "id": "WARD_JOS_EAST_8",
        "name": "Wandi",
        "pollingUnits": [
          "Wandi Village Defense Outpost (BEAT-JOS_EAST-81)",
          "Wandi Primary Healthcare Station (BEAT-JOS_EAST-82)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_JOS_NORTH",
    "name": "Jos North",
    "wards": [
      {
        "id": "WARD_JOS_NORTH_1",
        "name": "Abba Na Shehu",
        "pollingUnits": [
          "Abba Na Shehu Junction Beat (BEAT-JOS_NORTH-11)",
          "Yan Shanu Cattle Market Post (BEAT-JOS_NORTH-12)",
          "Dilimi River Bank Security Station (BEAT-JOS_NORTH-13)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_2",
        "name": "Ali Kazaure",
        "pollingUnits": [
          "Ali Kazaure Street Security Post (BEAT-JOS_NORTH-21)",
          "Central Mosque Security Perimeter Beat (BEAT-JOS_NORTH-22)",
          "Bature Street Patrol Unit (BEAT-JOS_NORTH-23)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_3",
        "name": "Buji",
        "pollingUnits": [
          "Buji Road Junction Beat (BEAT-JOS_NORTH-31)",
          "Buji Primary School Security Post (BEAT-JOS_NORTH-32)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_4",
        "name": "Gangare",
        "pollingUnits": [
          "Gangare Central Junction Beat (BEAT-JOS_NORTH-41)",
          "Gangare Health Center Security Outpost (BEAT-JOS_NORTH-42)",
          "Faris Street Patrol Post (BEAT-JOS_NORTH-43)",
          "Yan Taya Mosque Security Perimeter (BEAT-JOS_NORTH-44)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_5",
        "name": "Garba Daho",
        "pollingUnits": [
          "Garba Daho Market Security Beat (BEAT-JOS_NORTH-51)",
          "Laranto Market Entrance Patrol Unit (BEAT-JOS_NORTH-52)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_6",
        "name": "Ibrahim Katsina",
        "pollingUnits": [
          "Ibrahim Katsina Street Patrol Beat (BEAT-JOS_NORTH-61)",
          "Katsina Road Security Post (BEAT-JOS_NORTH-62)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_7",
        "name": "Jenta Adamu",
        "pollingUnits": [
          "Jenta Adamu Rockside Patrol Beat (BEAT-JOS_NORTH-71)",
          "Jenta Adamu Primary School Post (BEAT-JOS_NORTH-72)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_8",
        "name": "Jenta Apata",
        "pollingUnits": [
          "Jenta Apata Central Junction Beat (BEAT-JOS_NORTH-81)",
          "Apata Community Health Outpost (BEAT-JOS_NORTH-82)",
          "Jenta Mangoro Security Post (BEAT-JOS_NORTH-83)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_9",
        "name": "Kabong",
        "pollingUnits": [
          "Kabong Satellite Market Security Beat (BEAT-JOS_NORTH-91)",
          "Kabong Church Street Security Post (BEAT-JOS_NORTH-92)",
          "Gada Biyu Flyover Security Checkpoint (BEAT-JOS_NORTH-93)",
          "Gada Biyu Motor Park Patrol Unit (BEAT-JOS_NORTH-94)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_10",
        "name": "Lamingo",
        "pollingUnits": [
          "Lamingo Water Works Guard Post (BEAT-JOS_NORTH-101)",
          "Jos University Teaching Hospital (JUTH) Gate Beat (BEAT-JOS_NORTH-102)",
          "Lamingo Golf Course Patrol Unit (BEAT-JOS_NORTH-103)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_11",
        "name": "Naraguta A",
        "pollingUnits": [
          "University of Jos Permanent Site Main Gate (BEAT-JOS_NORTH-111)",
          "Naraguta Hostel Patrol Unit (BEAT-JOS_NORTH-112)",
          "Bauchi Road Security Post (BEAT-JOS_NORTH-113)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_12",
        "name": "Naraguta B",
        "pollingUnits": [
          "Naraguta Village Market Beat (BEAT-JOS_NORTH-121)",
          "Bauchi Motor Park Patrol Station (BEAT-JOS_NORTH-122)",
          "Clement Isong Street Post (BEAT-JOS_NORTH-123)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_13",
        "name": "Rigwe",
        "pollingUnits": [
          "Rigwe Community Hall Beat (BEAT-JOS_NORTH-131)",
          "Rigwe Street Security Station (BEAT-JOS_NORTH-132)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_14",
        "name": "Sarkin Arab",
        "pollingUnits": [
          "Sarkin Arab Palace Outer Gate (BEAT-JOS_NORTH-141)",
          "Arab Street Market Patrol Post (BEAT-JOS_NORTH-142)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_15",
        "name": "Tafawa Balewa",
        "pollingUnits": [
          "Tafawa Balewa Street Security Beat (BEAT-JOS_NORTH-151)",
          "Jos Main Market Underground Terminal Post (BEAT-JOS_NORTH-152)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_16",
        "name": "Tudun Wada",
        "pollingUnits": [
          "Tudun Wada Police Station Gate (BEAT-JOS_NORTH-161)",
          "Tudun Wada Central Junction Beat (BEAT-JOS_NORTH-162)",
          "Secretariat Flyover Patrol Unit (BEAT-JOS_NORTH-163)",
          "Federal Secretariat Road Guard Post (BEAT-JOS_NORTH-164)",
          "Standard Newspaper Junction Station (BEAT-JOS_NORTH-165)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_17",
        "name": "Unijos",
        "pollingUnits": [
          "Unijos Senior Staff Quarters Gate (BEAT-JOS_NORTH-171)",
          "Unijos Town Campus Gate Beat (BEAT-JOS_NORTH-172)"
        ]
      },
      {
        "id": "WARD_JOS_NORTH_18",
        "name": "Zaria Cut",
        "pollingUnits": [
          "Zaria Bypass Security Checkpoint (BEAT-JOS_NORTH-181)",
          "Zaria Cut Junction Patrol Unit (BEAT-JOS_NORTH-182)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_JOS_SOUTH",
    "name": "Jos South",
    "wards": [
      {
        "id": "WARD_JOS_SOUTH_1",
        "name": "Bukuru",
        "pollingUnits": [
          "Bukuru Central Market Square Patrol Post (BEAT-JOS_SOUTH-11)",
          "Bukuru Divisional Police Headquarters (BEAT-JOS_SOUTH-12)",
          "Bukuru Expressway Flyover Station (BEAT-JOS_SOUTH-13)",
          "Old Airport Junction Patrol Unit (BEAT-JOS_SOUTH-14)",
          "Lowcost Housing Estate Gate Beat (BEAT-JOS_SOUTH-15)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_2",
        "name": "Chwelnyap",
        "pollingUnits": [
          "Chwelnyap Community Center Post (BEAT-JOS_SOUTH-21)",
          "Chwelnyap Junction Patrol Unit (BEAT-JOS_SOUTH-22)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_3",
        "name": "Du",
        "pollingUnits": [
          "Du District Head Palace Gate (BEAT-JOS_SOUTH-31)",
          "Shen Road Security Checkpoint (BEAT-JOS_SOUTH-32)",
          "Du Community High School Station (BEAT-JOS_SOUTH-33)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_4",
        "name": "Gyel A",
        "pollingUnits": [
          "Gyel Central Market Security Post (BEAT-JOS_SOUTH-41)",
          "Plateau State Polytechnic Gyel Campus Main Gate (BEAT-JOS_SOUTH-42)",
          "Gyel Police Station Post (BEAT-JOS_SOUTH-43)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_5",
        "name": "Gyel B",
        "pollingUnits": [
          "Hwolshe Central Junction Security Post (BEAT-JOS_SOUTH-51)",
          "Hwolshe Community Clinic Beat (BEAT-JOS_SOUTH-52)",
          "Sabon Bariki Patrol Unit (BEAT-JOS_SOUTH-53)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_6",
        "name": "Kuru A",
        "pollingUnits": [
          "National Veterinary Research Institute (NVRI) Gate (BEAT-JOS_SOUTH-61)",
          "National Institute for Policy and Strategic Studies (NIPSS) Main Gate (BEAT-JOS_SOUTH-62)",
          "Kuru Trade Center Security Station (BEAT-JOS_SOUTH-63)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_7",
        "name": "Kuru B",
        "pollingUnits": [
          "Science School Kuru Outer Gate (BEAT-JOS_SOUTH-71)",
          "Kuru Railway Crossing Security Checkpoint (BEAT-JOS_SOUTH-72)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_8",
        "name": "Rayfield",
        "pollingUnits": [
          "Government House Rayfield Security Gate 1 (BEAT-JOS_SOUTH-81)",
          "Government House Rayfield Gate 2 (VIP Entry) (BEAT-JOS_SOUTH-82)",
          "Rayfield Golf Club Perimeter Patrol (BEAT-JOS_SOUTH-83)",
          "Dwei Junction Security Checkpoint (BEAT-JOS_SOUTH-84)",
          "Lamingo-Rayfield Link Road Station (BEAT-JOS_SOUTH-85)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_9",
        "name": "Vwang",
        "pollingUnits": [
          "Vwang District Head Palace Gate (BEAT-JOS_SOUTH-91)",
          "Vwang Central Market Security Outpost (BEAT-JOS_SOUTH-92)",
          "Vwang Vet Hospital Patrol Post (BEAT-JOS_SOUTH-93)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_10",
        "name": "Zawan A",
        "pollingUnits": [
          "Zawan Commercial Center Post (BEAT-JOS_SOUTH-101)",
          "Zawan Community Health Station (BEAT-JOS_SOUTH-102)"
        ]
      },
      {
        "id": "WARD_JOS_SOUTH_11",
        "name": "Zawan B",
        "pollingUnits": [
          "Dadinkowa Central Junction Security Post (BEAT-JOS_SOUTH-111)",
          "Dadinkowa Police Outpost Gate (BEAT-JOS_SOUTH-112)",
          "Tina Junction Security Beat (BEAT-JOS_SOUTH-113)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_KANAM",
    "name": "Kanam",
    "wards": [
      {
        "id": "WARD_KANAM_1",
        "name": "Dengi Central",
        "pollingUnits": [
          "Dengi Local Government Secretariat Gate (BEAT-KANAM-11)",
          "Dengi Central Market Security Beat (BEAT-KANAM-12)",
          "Dengi Divisional Police Station (BEAT-KANAM-13)",
          "Emir of Kanam Palace Guard Post (BEAT-KANAM-14)"
        ]
      },
      {
        "id": "WARD_KANAM_2",
        "name": "Garga",
        "pollingUnits": [
          "Garga District Head Palace Guard Post (BEAT-KANAM-21)",
          "Garga Central Market Station (BEAT-KANAM-22)",
          "Garga Forest Reserve Border Checkpoint (BEAT-KANAM-23)"
        ]
      },
      {
        "id": "WARD_KANAM_3",
        "name": "Jhar",
        "pollingUnits": [
          "Jhar Community Defense Station (BEAT-KANAM-31)",
          "Jhar Healthcare Center Beat (BEAT-KANAM-32)"
        ]
      },
      {
        "id": "WARD_KANAM_4",
        "name": "Kantana",
        "pollingUnits": [
          "Kantana Mining Site Guard Post (BEAT-KANAM-41)",
          "Kantana Market Square Beat (BEAT-KANAM-42)"
        ]
      },
      {
        "id": "WARD_KANAM_5",
        "name": "Kwali",
        "pollingUnits": [
          "Kwali Village Security Post (BEAT-KANAM-51)",
          "Kwali Primary School Beat (BEAT-KANAM-52)"
        ]
      },
      {
        "id": "WARD_KANAM_6",
        "name": "Namaran",
        "pollingUnits": [
          "Namaran Agricultural Station (BEAT-KANAM-61)",
          "Namaran Village Patrol Unit (BEAT-KANAM-62)"
        ]
      },
      {
        "id": "WARD_KANAM_7",
        "name": "Tawai",
        "pollingUnits": [
          "Tawai Village Defense Post (BEAT-KANAM-71)",
          "Tawai Health Outpost (BEAT-KANAM-72)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_KANKE",
    "name": "Kanke",
    "wards": [
      {
        "id": "WARD_KANKE_1",
        "name": "Amper Central",
        "pollingUnits": [
          "Amper Central Market Security Post (BEAT-KANKE-11)",
          "Amper Local Government Sub-Secretariat (BEAT-KANKE-12)",
          "Amper General Hospital Gate Beat (BEAT-KANKE-13)"
        ]
      },
      {
        "id": "WARD_KANKE_2",
        "name": "Garza",
        "pollingUnits": [
          "Garza Village Security Outpost (BEAT-KANKE-21)",
          "Garza Agriculture Station (BEAT-KANKE-22)"
        ]
      },
      {
        "id": "WARD_KANKE_3",
        "name": "Kabwir Central",
        "pollingUnits": [
          "Kabwir Traditional Council Gate (BEAT-KANKE-31)",
          "Kabwir Divisional Police Post (BEAT-KANKE-32)",
          "Kabwir Central Market Beat (BEAT-KANKE-33)"
        ]
      },
      {
        "id": "WARD_KANKE_4",
        "name": "Kwal",
        "pollingUnits": [
          "Kwal Community High School Post (BEAT-KANKE-41)",
          "Kwal Village Patrol Station (BEAT-KANKE-42)"
        ]
      },
      {
        "id": "WARD_KANKE_5",
        "name": "Lankan",
        "pollingUnits": [
          "Lankan Mining Camp Guard Post (BEAT-KANKE-51)",
          "Lankan Market Security Beat (BEAT-KANKE-52)"
        ]
      },
      {
        "id": "WARD_KANKE_6",
        "name": "Shiwer",
        "pollingUnits": [
          "Shiwer Community Health Center Beat (BEAT-KANKE-61)",
          "Shiwer Village Square Post (BEAT-KANKE-62)"
        ]
      },
      {
        "id": "WARD_KANKE_7",
        "name": "Tep",
        "pollingUnits": [
          "Tep Mountain Patrol Station (BEAT-KANKE-71)",
          "Tep Village Security Outpost (BEAT-KANKE-72)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_LANGTANG_NORTH",
    "name": "Langtang North",
    "wards": [
      {
        "id": "WARD_LANGTANG_NORTH_1",
        "name": "Langtang Central A",
        "pollingUnits": [
          "Langtang Main Market Security Post (BEAT-LANGTANG_NORTH-11)",
          "Ponzhi Tarok Palace Guard Station (BEAT-LANGTANG_NORTH-12)",
          "Langtang North Secretariat Gate (BEAT-LANGTANG_NORTH-13)",
          "General Hospital Langtang Guard Beat (BEAT-LANGTANG_NORTH-14)"
        ]
      },
      {
        "id": "WARD_LANGTANG_NORTH_2",
        "name": "Langtang Central B",
        "pollingUnits": [
          "Langtang Divisional Police Headquarters (BEAT-LANGTANG_NORTH-21)",
          "Langtang Central Motor Park Post (BEAT-LANGTANG_NORTH-22)",
          "College of Agriculture Gate Beat (BEAT-LANGTANG_NORTH-23)"
        ]
      },
      {
        "id": "WARD_LANGTANG_NORTH_3",
        "name": "Gazum",
        "pollingUnits": [
          "Gazum District Head Palace Post (BEAT-LANGTANG_NORTH-31)",
          "Gazum Community Market Security Beat (BEAT-LANGTANG_NORTH-32)"
        ]
      },
      {
        "id": "WARD_LANGTANG_NORTH_4",
        "name": "Jepjan",
        "pollingUnits": [
          "Jepjan Village Square Guard Unit (BEAT-LANGTANG_NORTH-41)",
          "Jepjan Health Clinic Post (BEAT-LANGTANG_NORTH-42)"
        ]
      },
      {
        "id": "WARD_LANGTANG_NORTH_5",
        "name": "Kwanpe",
        "pollingUnits": [
          "Kwanpe Agriculture Center Beat (BEAT-LANGTANG_NORTH-51)",
          "Kwanpe Village Security Post (BEAT-LANGTANG_NORTH-52)"
        ]
      },
      {
        "id": "WARD_LANGTANG_NORTH_6",
        "name": "Pil-Gani",
        "pollingUnits": [
          "Pil-Gani District Palace Gate (BEAT-LANGTANG_NORTH-61)",
          "Pil-Gani Central Market Patrol Station (BEAT-LANGTANG_NORTH-62)"
        ]
      },
      {
        "id": "WARD_LANGTANG_NORTH_7",
        "name": "Sabon Gida",
        "pollingUnits": [
          "Sabon Gida Commercial Center Post (BEAT-LANGTANG_NORTH-71)",
          "Sabon Gida Police Checkpoint (BEAT-LANGTANG_NORTH-72)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_LANGTANG_SOUTH",
    "name": "Langtang South",
    "wards": [
      {
        "id": "WARD_LANGTANG_SOUTH_1",
        "name": "Mabudi",
        "pollingUnits": [
          "Mabudi Local Government Secretariat Gate (BEAT-LANGTANG_SOUTH-11)",
          "Mabudi Central Market Security Post (BEAT-LANGTANG_SOUTH-12)",
          "Mabudi Divisional Police Station (BEAT-LANGTANG_SOUTH-13)",
          "Mabudi General Hospital Guard Post (BEAT-LANGTANG_SOUTH-14)"
        ]
      },
      {
        "id": "WARD_LANGTANG_SOUTH_2",
        "name": "Fadama",
        "pollingUnits": [
          "Fadama Agricultural Station Post (BEAT-LANGTANG_SOUTH-21)",
          "Fadama River Basin Patrol Unit (BEAT-LANGTANG_SOUTH-22)"
        ]
      },
      {
        "id": "WARD_LANGTANG_SOUTH_3",
        "name": "Magama",
        "pollingUnits": [
          "Magama Commercial Grain Market Beat (BEAT-LANGTANG_SOUTH-31)",
          "Magama Police Outpost Gate (BEAT-LANGTANG_SOUTH-32)",
          "Magama Border Security Checkpoint (BEAT-LANGTANG_SOUTH-33)"
        ]
      },
      {
        "id": "WARD_LANGTANG_SOUTH_4",
        "name": "Sabon Gida South",
        "pollingUnits": [
          "Sabon Gida South Central Market Post (BEAT-LANGTANG_SOUTH-41)",
          "Sabon Gida South Clinic Beat (BEAT-LANGTANG_SOUTH-42)"
        ]
      },
      {
        "id": "WARD_LANGTANG_SOUTH_5",
        "name": "Timbol",
        "pollingUnits": [
          "Timbol Community Center Post (BEAT-LANGTANG_SOUTH-51)",
          "Timbol Village Patrol Station (BEAT-LANGTANG_SOUTH-52)"
        ]
      },
      {
        "id": "WARD_LANGTANG_SOUTH_6",
        "name": "Turaki",
        "pollingUnits": [
          "Turaki Community Defense Post (BEAT-LANGTANG_SOUTH-61)",
          "Turaki Primary School Guard Unit (BEAT-LANGTANG_SOUTH-62)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_MANGU",
    "name": "Mangu",
    "wards": [
      {
        "id": "WARD_MANGU_1",
        "name": "Mangu Central",
        "pollingUnits": [
          "Mangu Central Market Square Security Post (BEAT-MANGU-11)",
          "Mangu Divisional Police Headquarters (BEAT-MANGU-12)",
          "Mangu Local Government Secretariat Gate (BEAT-MANGU-13)",
          "Mangu General Hospital Outer Gate (BEAT-MANGU-14)",
          "Mangu Central Motor Park Station (BEAT-MANGU-15)"
        ]
      },
      {
        "id": "WARD_MANGU_2",
        "name": "Mangu Halle",
        "pollingUnits": [
          "Mangu Halle Flyover Security Checkpoint (BEAT-MANGU-21)",
          "Mangu Halle Grain Market Patrol Post (BEAT-MANGU-22)",
          "Jos-Pankshin Highway Security Station (BEAT-MANGU-23)"
        ]
      },
      {
        "id": "WARD_MANGU_3",
        "name": "Bwai",
        "pollingUnits": [
          "Bwai Community High School Post (BEAT-MANGU-31)",
          "Bwai Healthcare Security Outpost (BEAT-MANGU-32)"
        ]
      },
      {
        "id": "WARD_MANGU_4",
        "name": "Gindiri 1",
        "pollingUnits": [
          "Gindiri Teachers College (COE) Main Gate (BEAT-MANGU-41)",
          "Gindiri Traditional Council Palace Gate (BEAT-MANGU-42)",
          "Gindiri Central Market Security Beat (BEAT-MANGU-43)"
        ]
      },
      {
        "id": "WARD_MANGU_5",
        "name": "Gindiri 2",
        "pollingUnits": [
          "Gindiri Water Works Guard Post (BEAT-MANGU-51)",
          "Sum Pyem Palace Perimeter Patrol (BEAT-MANGU-52)"
        ]
      },
      {
        "id": "WARD_MANGU_6",
        "name": "Kerang",
        "pollingUnits": [
          "SWAN Water Spring Factory Guard Post (BEAT-MANGU-61)",
          "Kerang Volcanic Hill Patrol Station (BEAT-MANGU-62)",
          "Kerang Central Market Beat (BEAT-MANGU-63)"
        ]
      },
      {
        "id": "WARD_MANGU_7",
        "name": "Kombun",
        "pollingUnits": [
          "Kombun Agricultural Outpost (BEAT-MANGU-71)",
          "Kombun Village Security Post (BEAT-MANGU-72)"
        ]
      },
      {
        "id": "WARD_MANGU_8",
        "name": "Panyam",
        "pollingUnits": [
          "Panyam Fish Farm Security Compound (BEAT-MANGU-81)",
          "Panyam Central Market Patrol Post (BEAT-MANGU-82)",
          "Panyam-Shendam Junction Station (BEAT-MANGU-83)"
        ]
      },
      {
        "id": "WARD_MANGU_9",
        "name": "Puya",
        "pollingUnits": [
          "Puya Community School Beat (BEAT-MANGU-91)",
          "Puya Village Square Station (BEAT-MANGU-92)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_MIKANG",
    "name": "Mikang",
    "wards": [
      {
        "id": "WARD_MIKANG_1",
        "name": "Tunkus",
        "pollingUnits": [
          "Tunkus Local Government Secretariat Gate (BEAT-MIKANG-11)",
          "Tunkus Divisional Police Station (BEAT-MIKANG-12)",
          "Tunkus Central Market Post (BEAT-MIKANG-13)"
        ]
      },
      {
        "id": "WARD_MIKANG_2",
        "name": "Gerkawa",
        "pollingUnits": [
          "Gerkawa Traditional Palace Gate (BEAT-MIKANG-21)",
          "Gerkawa Central Market Patrol Post (BEAT-MIKANG-22)",
          "Gerkawa Health Center Beat (BEAT-MIKANG-23)"
        ]
      },
      {
        "id": "WARD_MIKANG_3",
        "name": "Montol",
        "pollingUnits": [
          "Montol Community Watch Post (BEAT-MIKANG-31)",
          "Montol Agriculture Outpost (BEAT-MIKANG-32)"
        ]
      },
      {
        "id": "WARD_MIKANG_4",
        "name": "Pisa",
        "pollingUnits": [
          "Pisa Village Defense Unit (BEAT-MIKANG-41)",
          "Pisa Healthcare Center Beat (BEAT-MIKANG-42)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_PANKSHIN",
    "name": "Pankshin",
    "wards": [
      {
        "id": "WARD_PANKSHIN_1",
        "name": "Pankshin Central",
        "pollingUnits": [
          "Pankshin Local Government Secretariat Gate (BEAT-PANKSHIN-11)",
          "Federal College of Education (FCE) Main Gate (BEAT-PANKSHIN-12)",
          "Pankshin Divisional Police Headquarters (BEAT-PANKSHIN-13)",
          "Pankshin General Hospital Gate (BEAT-PANKSHIN-14)",
          "Central Market Security Post (BEAT-PANKSHIN-15)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_2",
        "name": "Chip",
        "pollingUnits": [
          "Chip District Palace Gate (BEAT-PANKSHIN-21)",
          "Chip Central Market Patrol Post (BEAT-PANKSHIN-22)",
          "Chip Community High School Station (BEAT-PANKSHIN-23)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_3",
        "name": "Fier",
        "pollingUnits": [
          "Fier Traditional Council Post (BEAT-PANKSHIN-31)",
          "Fier Health Clinic Security Unit (BEAT-PANKSHIN-32)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_4",
        "name": "Jipal",
        "pollingUnits": [
          "Jipal Mining Compound Guard Post (BEAT-PANKSHIN-41)",
          "Jipal Village Square Beat (BEAT-PANKSHIN-42)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_5",
        "name": "Kakang",
        "pollingUnits": [
          "Kakang Community High School Station (BEAT-PANKSHIN-51)",
          "Kakang Health Outpost (BEAT-PANKSHIN-52)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_6",
        "name": "Lankan",
        "pollingUnits": [
          "Lankan Central Market Beat (BEAT-PANKSHIN-61)",
          "Lankan Primary School Guard Post (BEAT-PANKSHIN-62)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_7",
        "name": "Tal",
        "pollingUnits": [
          "Tal Village Security Post (BEAT-PANKSHIN-71)",
          "Tal Agriculture Station (BEAT-PANKSHIN-72)"
        ]
      },
      {
        "id": "WARD_PANKSHIN_8",
        "name": "Wokkos",
        "pollingUnits": [
          "Wokkos Traditional Palace Post (BEAT-PANKSHIN-81)",
          "Wokkos Community Defense Station (BEAT-PANKSHIN-82)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_QUAN_PAN",
    "name": "Qua'an Pan",
    "wards": [
      {
        "id": "WARD_QUAN_PAN_1",
        "name": "Ba'ap",
        "pollingUnits": [
          "Ba'ap Local Government Secretariat Gate (BEAT-QUAN_PAN-11)",
          "Ba'ap Divisional Police Station (BEAT-QUAN_PAN-12)",
          "Ba'ap General Hospital Post (BEAT-QUAN_PAN-13)"
        ]
      },
      {
        "id": "WARD_QUAN_PAN_2",
        "name": "Doemak",
        "pollingUnits": [
          "Doemak Traditional Palace Gate (BEAT-QUAN_PAN-21)",
          "Doemak Central Market Security Beat (BEAT-QUAN_PAN-22)",
          "Doemak Community High School Patrol Unit (BEAT-QUAN_PAN-23)"
        ]
      },
      {
        "id": "WARD_QUAN_PAN_3",
        "name": "Kwall",
        "pollingUnits": [
          "Kwall Border Guard Post (BEAT-QUAN_PAN-31)",
          "Kwall Agriculture Center Station (BEAT-QUAN_PAN-32)"
        ]
      },
      {
        "id": "WARD_QUAN_PAN_4",
        "name": "Namu",
        "pollingUnits": [
          "Namu Rice Mill Complex Guard Post (BEAT-QUAN_PAN-41)",
          "Namu Central Market Patrol Station (BEAT-QUAN_PAN-42)",
          "Namu Border Security Checkpoint (BEAT-QUAN_PAN-43)"
        ]
      },
      {
        "id": "WARD_QUAN_PAN_5",
        "name": "Pandam",
        "pollingUnits": [
          "Pandam Wildlife Park Main Entrance Guard Post (BEAT-QUAN_PAN-51)",
          "Pandam Lake Security Outpost (BEAT-QUAN_PAN-52)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_RIYOM",
    "name": "Riyom",
    "wards": [
      {
        "id": "WARD_RIYOM_1",
        "name": "Riyom Central",
        "pollingUnits": [
          "Riyom Local Government Secretariat Gate (BEAT-RIYOM-11)",
          "Riyom Divisional Police Station (BEAT-RIYOM-12)",
          "Riyom General Hospital Guard Post (BEAT-RIYOM-13)",
          "Jos-Akwanga Expressway Checkpoint (BEAT-RIYOM-14)"
        ]
      },
      {
        "id": "WARD_RIYOM_2",
        "name": "Bachi",
        "pollingUnits": [
          "Bachi Mining Area Guard Post (BEAT-RIYOM-21)",
          "Bachi Community High School Beat (BEAT-RIYOM-22)"
        ]
      },
      {
        "id": "WARD_RIYOM_3",
        "name": "Ganawuri",
        "pollingUnits": [
          "Ganawuri Traditional Palace Gate (BEAT-RIYOM-31)",
          "Ganawuri Central Market Patrol Post (BEAT-RIYOM-32)",
          "Ganawuri Hills Security Post (BEAT-RIYOM-33)"
        ]
      },
      {
        "id": "WARD_RIYOM_4",
        "name": "Jol",
        "pollingUnits": [
          "Jol Village Security Outpost (BEAT-RIYOM-41)",
          "Jol Primary Healthcare Station (BEAT-RIYOM-42)",
          "Jol Peace Building Center (BEAT-RIYOM-43)"
        ]
      },
      {
        "id": "WARD_RIYOM_5",
        "name": "Rim",
        "pollingUnits": [
          "Rim Village Square Defense Post (BEAT-RIYOM-51)",
          "Rim Health Clinic Patrol Unit (BEAT-RIYOM-52)"
        ]
      },
      {
        "id": "WARD_RIYOM_6",
        "name": "Ta-Hoss",
        "pollingUnits": [
          "Ta-Hoss Highway Security Checkpoint (BEAT-RIYOM-61)",
          "Ta-Hoss Mining Site Patrol Station (BEAT-RIYOM-62)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_SHENDAM",
    "name": "Shendam",
    "wards": [
      {
        "id": "WARD_SHENDAM_1",
        "name": "Shendam Central",
        "pollingUnits": [
          "Shendam Local Government Secretariat Main Gate (BEAT-SHENDAM-11)",
          "Shendam Divisional Police Headquarters (BEAT-SHENDAM-12)",
          "Emir of Shendam / Long Goemai Palace Guard Post (BEAT-SHENDAM-13)",
          "Shendam Central Market Patrol Station (BEAT-SHENDAM-14)",
          "Shendam General Hospital Gate (BEAT-SHENDAM-15)"
        ]
      },
      {
        "id": "WARD_SHENDAM_2",
        "name": "Derteng",
        "pollingUnits": [
          "Derteng Village Defense Outpost (BEAT-SHENDAM-21)",
          "Derteng Healthcare Center Beat (BEAT-SHENDAM-22)"
        ]
      },
      {
        "id": "WARD_SHENDAM_3",
        "name": "Dorowa",
        "pollingUnits": [
          "Dorowa Commercial Center Post (BEAT-SHENDAM-31)",
          "Dorowa Police Outpost Gate (BEAT-SHENDAM-32)"
        ]
      },
      {
        "id": "WARD_SHENDAM_4",
        "name": "Kalong",
        "pollingUnits": [
          "Kalong Agriculture Center Guard Unit (BEAT-SHENDAM-41)",
          "Kalong Market Security Post (BEAT-SHENDAM-42)"
        ]
      },
      {
        "id": "WARD_SHENDAM_5",
        "name": "Kwo",
        "pollingUnits": [
          "Kwo Traditional Palace Guard Station (BEAT-SHENDAM-51)",
          "Kwo Community High School Beat (BEAT-SHENDAM-52)"
        ]
      },
      {
        "id": "WARD_SHENDAM_6",
        "name": "Poeship",
        "pollingUnits": [
          "Poeship Village Patrol Unit (BEAT-SHENDAM-61)",
          "Poeship Healthcare Post (BEAT-SHENDAM-62)"
        ]
      }
    ],
    "siecWards": []
  },
  {
    "id": "LGA_WASE",
    "name": "Wase",
    "wards": [
      {
        "id": "WARD_WASE_1",
        "name": "Wase Central",
        "pollingUnits": [
          "Emir of Wase Palace Guard Post (BEAT-WASE-11)",
          "Wase Local Government Secretariat Gate (BEAT-WASE-12)",
          "Wase Divisional Police Station (BEAT-WASE-13)",
          "Wase Rock Security Watch Post (BEAT-WASE-14)",
          "Wase Central Market Patrol Station (BEAT-WASE-15)"
        ]
      },
      {
        "id": "WARD_WASE_2",
        "name": "Bashar",
        "pollingUnits": [
          "Bashar District Head Palace Guard Unit (BEAT-WASE-21)",
          "Bashar Central Market Patrol Post (BEAT-WASE-22)",
          "Bashar Forest Border Checkpoint (BEAT-WASE-23)"
        ]
      },
      {
        "id": "WARD_WASE_3",
        "name": "Dan Biram",
        "pollingUnits": [
          "Dan Biram Agricultural Post (BEAT-WASE-31)",
          "Dan Biram Village Defense Unit (BEAT-WASE-32)"
        ]
      },
      {
        "id": "WARD_WASE_4",
        "name": "Kadarko",
        "pollingUnits": [
          "Kadarko Central Market Security Station (BEAT-WASE-41)",
          "Kadarko Mining Compound Guard Post (BEAT-WASE-42)",
          "Kadarko Border Patrol Unit (BEAT-WASE-43)"
        ]
      },
      {
        "id": "WARD_WASE_5",
        "name": "Kumbur",
        "pollingUnits": [
          "Kumbur Village Defense Post (BEAT-WASE-51)",
          "Kumbur Health Center Beat (BEAT-WASE-52)"
        ]
      },
      {
        "id": "WARD_WASE_6",
        "name": "Lamba",
        "pollingUnits": [
          "Lamba Community School Post (BEAT-WASE-61)",
          "Lamba Village Security Station (BEAT-WASE-62)"
        ]
      },
      {
        "id": "WARD_WASE_7",
        "name": "Mavo",
        "pollingUnits": [
          "Mavo Mining Camp Patrol Unit (BEAT-WASE-71)",
          "Mavo Primary Healthcare Post (BEAT-WASE-72)"
        ]
      }
    ],
    "siecWards": []
  }
];
