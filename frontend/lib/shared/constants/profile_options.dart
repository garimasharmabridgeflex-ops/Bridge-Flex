import 'package:flutter/material.dart';

import '../widgets/chip_multi_select.dart';

/// Curated chip option sets shared across the profile-edit, public-profile,
/// and shift-detail/post screens — full app spec profile-fields request:
/// "Facilities, show icons... requirements... Skills, display as chips".
/// Kept as plain value/label pairs (not enums) since these are open-ended
/// catalogs the product may extend without a data-migration story; storage
/// is always the raw string value.

const List<ChipOption> nurseryFacilityOptions = [
  ChipOption('free_parking', 'Free parking', icon: Icons.local_parking_outlined),
  ChipOption('staff_room', 'Staff room', icon: Icons.meeting_room_outlined),
  ChipOption('kitchen', 'Kitchen', icon: Icons.kitchen_outlined),
  ChipOption('outdoor_play_area', 'Outdoor play area', icon: Icons.park_outlined),
  ChipOption('wifi', 'Wifi', icon: Icons.wifi_rounded),
  ChipOption('cctv', 'CCTV', icon: Icons.videocam_outlined),
  ChipOption('disabled_access', 'Disabled access', icon: Icons.accessible_outlined),
  ChipOption('changing_facilities', 'Changing facilities', icon: Icons.baby_changing_station_outlined),
  ChipOption('sensory_room', 'Sensory room', icon: Icons.spa_outlined),
  ChipOption('sleep_room', 'Sleep room', icon: Icons.bedtime_outlined),
];

const List<ChipOption> staffSkillOptions = [
  ChipOption('baby_room', 'Baby room'),
  ChipOption('toddler_room', 'Toddler room'),
  ChipOption('preschool', 'Preschool'),
  ChipOption('sen_experience', 'SEN experience'),
  ChipOption('forest_school', 'Forest school'),
  ChipOption('montessori', 'Montessori'),
  ChipOption('outdoor_learning', 'Outdoor learning'),
  ChipOption('food_hygiene', 'Food hygiene'),
  ChipOption('key_worker', 'Key worker'),
  ChipOption('behaviour_management', 'Behaviour management'),
];

const List<ChipOption> staffQualificationOptions = [
  ChipOption('level_2', 'Level 2'),
  ChipOption('level_3', 'Level 3'),
  ChipOption('level_4_plus', 'Level 4+'),
  ChipOption('paediatric_first_aid', 'Paediatric first aid'),
  ChipOption('senco', 'SENCO'),
  ChipOption('safeguarding_lead', 'Safeguarding lead'),
  ChipOption('montessori_diploma', 'Montessori diploma'),
  ChipOption('early_years_degree', 'Early years degree'),
];

// Requirements minimums a nursery can set on a shift — same catalog as
// staffQualificationOptions plus a couple of shift-specific extras.
const List<ChipOption> shiftRequirementOptions = [
  ChipOption('level_1', 'Level 1'),
  ChipOption('level_2', 'Level 2'),
  ChipOption('level_3', 'Level 3'),
  ChipOption('paediatric_first_aid', 'Paediatric first aid'),
  ChipOption('sen_experience', 'SEN experience'),
  ChipOption('baby_room_experience', 'Baby room experience'),
  ChipOption('dbs_required', 'DBS required'),
];

const List<ChipOption> shiftDutyOptions = [
  ChipOption('nappy_changing', 'Nappy changing'),
  ChipOption('meal_prep', 'Meal prep'),
  ChipOption('outdoor_supervision', 'Outdoor supervision'),
  ChipOption('story_time', 'Story time'),
  ChipOption('art_activities', 'Art activities'),
  ChipOption('nap_time_supervision', 'Nap time supervision'),
  ChipOption('cleaning', 'Cleaning'),
  ChipOption('key_worker_duties', 'Key worker duties'),
];

const List<ChipOption> availabilityDayOptions = [
  ChipOption('monday', 'Mon'),
  ChipOption('tuesday', 'Tue'),
  ChipOption('wednesday', 'Wed'),
  ChipOption('thursday', 'Thu'),
  ChipOption('friday', 'Fri'),
  ChipOption('saturday', 'Sat'),
  ChipOption('sunday', 'Sun'),
];

const List<ChipOption> availabilityShiftOptions = [
  ChipOption('morning', 'Morning', icon: Icons.wb_sunny_outlined),
  ChipOption('afternoon', 'Afternoon', icon: Icons.wb_cloudy_outlined),
  ChipOption('evening', 'Evening', icon: Icons.nights_stay_outlined),
  ChipOption('night', 'Night', icon: Icons.bedtime_outlined),
];

const List<String> ageGroupOptions = [
  'Babies (0-2)',
  'Toddlers (2-3)',
  'Preschool (3-5)',
  'Mixed ages',
];

// Right-to-work status categories — chip-selectable instead of free text, so
// the value stays consistent for future filtering (full app spec: "right to
// work... visa status").
const List<ChipOption> visaStatusOptions = [
  ChipOption('british_irish_citizen', 'British / Irish citizen'),
  ChipOption('settled_status', 'Settled status (ILR)'),
  ChipOption('pre_settled_status', 'Pre-settled status'),
  ChipOption('skilled_worker_visa', 'Skilled Worker visa'),
  ChipOption('health_care_worker_visa', 'Health & Care Worker visa'),
  ChipOption('student_visa', 'Student visa (with work rights)'),
  ChipOption('other_visa', 'Other visa'),
  ChipOption('not_applicable', 'Not applicable'),
];

const List<ChipOption> rightToWorkStatusOptions = [
  ChipOption('unrestricted', 'Unrestricted right to work'),
  ChipOption('time_limited', 'Time-limited right to work'),
  ChipOption('not_yet_confirmed', 'Not yet confirmed'),
];

/// Maps a stored chip value back to its display label for read-only views —
/// falls back to the raw stored string for legacy free-text data saved
/// before these became fixed chip sets.
String visaStatusLabel(String value) =>
    visaStatusOptions.where((o) => o.value == value).firstOrNull?.label ?? value;

String rightToWorkStatusLabel(String value) =>
    rightToWorkStatusOptions.where((o) => o.value == value).firstOrNull?.label ?? value;

/// Quick-fill presets for the nursery "Opening hours" field — still a free
/// text field underneath (hours genuinely vary), these just cut typing for
/// the common cases.
const List<String> openingHoursPresets = [
  'Mon–Fri, 7:30am–6:00pm',
  'Mon–Fri, 8:00am–6:00pm',
  'Mon–Fri, 7:00am–7:00pm',
  'Mon–Sat, 8:00am–6:00pm',
];

/// Common languages spoken by nursery staff in the UK — chip-selectable
/// shortcut in front of the free-text [ChipTagInput] for anything not
/// listed (full app spec: "Languages spoken").
const List<ChipOption> commonLanguageOptions = [
  ChipOption('english', 'English'),
  ChipOption('polish', 'Polish'),
  ChipOption('romanian', 'Romanian'),
  ChipOption('portuguese', 'Portuguese'),
  ChipOption('urdu', 'Urdu'),
  ChipOption('punjabi', 'Punjabi'),
  ChipOption('bengali', 'Bengali'),
  ChipOption('gujarati', 'Gujarati'),
  ChipOption('hindi', 'Hindi'),
  ChipOption('spanish', 'Spanish'),
  ChipOption('french', 'French'),
  ChipOption('arabic', 'Arabic'),
  ChipOption('somali', 'Somali'),
  ChipOption('lithuanian', 'Lithuanian'),
  ChipOption('tagalog', 'Tagalog / Filipino'),
  ChipOption('yoruba', 'Yoruba'),
  ChipOption('italian', 'Italian'),
  ChipOption('bulgarian', 'Bulgarian'),
];
