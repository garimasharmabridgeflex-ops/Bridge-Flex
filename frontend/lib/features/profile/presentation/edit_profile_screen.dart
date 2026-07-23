import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/constants/countries.dart';
import '../../../shared/constants/profile_options.dart';
import '../../../shared/constants/uk_locations.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/chip_multi_select.dart';
import '../../../shared/widgets/chip_or_other_select.dart';
import '../../../shared/widgets/labeled_autocomplete_field.dart';
import '../../../shared/widgets/number_stepper.dart';
import '../../../shared/widgets/phone_field.dart';
import '../../../shared/widgets/photo_source_sheet.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/uk_postcode_field.dart';
import '../domain/profile.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _openingHours = TextEditingController();
  final _bio = TextEditingController();

  // Nursery detail controllers.
  final _registeredCompanyName = TextEditingController();
  final _ofstedRegNumber = TextEditingController();
  final _website = TextEditingController();
  final _postcode = TextEditingController();
  final _email = TextEditingController();
  final _shortDescription = TextEditingController();

  // Staff detail controllers.
  final _city = TextEditingController();
  final _professionalSummary = TextEditingController();
  final _dbsCertificateNumber = TextEditingController();
  final _nationality = TextEditingController();

  String _fullPhone = '+44 ';
  bool _loading = false;
  bool _initialized = false;
  int _yearsExperience = 0;
  QualificationLevel _qualification = QualificationLevel.none;
  OfstedRating _ofsted = OfstedRating.notRated;
  String? _photoUrl;
  File? _newPhoto;
  List<String> _photos = [];

  NurseryType _nurseryType = NurseryType.unspecified;
  List<String> _facilities = [];
  int? _yearEstablishedValue;

  int? _age;
  int _travelDistanceMiles = 10;
  List<String> _languages = [];
  List<String> _qualifications = [];
  List<String> _skills = [];
  List<String> _availabilityDays = [];
  List<String> _availabilityShifts = [];
  DateTime? _dbsExpiryDate;
  String _visaStatus = '';
  String _rightToWorkStatus = '';

  void _hydrate(Profile profile) {
    if (_initialized) return;
    _name.text = profile.name;
    final (dialCode, local) = splitPhone(profile.phone);
    _phone.text = local;
    _fullPhone = profile.phone.isNotEmpty ? profile.phone : '$dialCode ';
    _description.text = profile.description;
    _address.text = profile.address;
    _openingHours.text = profile.openingHours;
    _bio.text = profile.bio;
    _yearsExperience = profile.yearsExperience;
    _qualification = profile.qualificationLevel;
    _ofsted = profile.ofstedRating;
    _photoUrl = profile.photoUrl.isNotEmpty ? profile.photoUrl : null;
    _photos = List<String>.from(profile.photos);

    _registeredCompanyName.text = profile.registeredCompanyName;
    _ofstedRegNumber.text = profile.ofstedRegNumber;
    _yearEstablishedValue = profile.yearEstablished > 0 ? profile.yearEstablished : null;
    _website.text = profile.website;
    _postcode.text = profile.postcode;
    _email.text = profile.email;
    _shortDescription.text = profile.shortDescription;
    _nurseryType = profile.nurseryType;
    _facilities = List<String>.from(profile.facilities);

    _age = profile.age;
    _city.text = profile.city;
    _professionalSummary.text = profile.professionalSummary;
    _dbsCertificateNumber.text = profile.dbsCertificateNumber;
    _nationality.text = profile.nationality;
    _visaStatus = profile.visaStatus;
    _rightToWorkStatus = profile.rightToWorkStatus;
    _travelDistanceMiles = profile.travelDistanceMiles > 0 ? profile.travelDistanceMiles : 10;
    _languages = List<String>.from(profile.languages);
    _qualifications = List<String>.from(profile.qualifications);
    _skills = List<String>.from(profile.skills);
    _availabilityDays = List<String>.from(profile.availabilityDays);
    _availabilityShifts = List<String>.from(profile.availabilityShifts);
    _dbsExpiryDate = profile.dbsExpiryDate;

    _initialized = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _description.dispose();
    _address.dispose();
    _openingHours.dispose();
    _bio.dispose();
    _registeredCompanyName.dispose();
    _ofstedRegNumber.dispose();
    _website.dispose();
    _postcode.dispose();
    _email.dispose();
    _shortDescription.dispose();
    _city.dispose();
    _professionalSummary.dispose();
    _dbsCertificateNumber.dispose();
    _nationality.dispose();
    super.dispose();
  }

  Future<void> _pickYearEstablished() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_yearEstablishedValue ?? now.year),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _yearEstablishedValue = picked.year);
  }

  Future<void> _pickPhoto() async {
    final picked = await pickImageWithSourceSheet(context);
    if (picked == null) return;
    setState(() => _newPhoto = File(picked.path));
  }

  static const _maxNurseryPhotos = 5;

  Future<void> _addNurseryPhoto() async {
    if (_photos.length >= _maxNurseryPhotos) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final picked = await pickImageWithSourceSheet(context);
    if (picked == null) return;
    setState(() => _loading = true);
    try {
      final url = await ref.read(profileRepositoryProvider).uploadNurseryPhoto(
            uid: user.uid,
            file: File(picked.path),
            index: _photos.length + 1,
          );
      setState(() => _photos.add(url));
      await ref.read(profileRepositoryProvider).updateProfile(photos: _photos);
      ref.invalidate(ownProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nursery photo added!')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDbsExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dbsExpiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _dbsExpiryDate = picked);
  }

  Future<void> _detectLocation() async {
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled on device.')),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied.')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission permanently denied.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      await ref.read(profileRepositoryProvider).updateProfile(
            lat: pos.latitude,
            lng: pos.longitude,
          );
      ref.invalidate(ownProfileProvider);
      final user = ref.read(authStateProvider).valueOrNull;
      if (user != null) {
        ref.invalidate(publicProfileProvider(user.uid));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Location logged: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(UserRole role) async {
    final user = ref.read(authStateProvider).valueOrNull;
    setState(() => _loading = true);
    try {
      String? uploadedPhotoUrl;
      if (_newPhoto != null && user != null) {
        uploadedPhotoUrl = await ref
            .read(profileRepositoryProvider)
            .uploadProfilePhoto(uid: user.uid, file: _newPhoto!);
      }
      await ref.read(profileRepositoryProvider).updateProfile(
            name: _name.text.trim(),
            phone: _fullPhone.trim(),
            photoUrl: uploadedPhotoUrl ?? _photoUrl,
            description: role == UserRole.nursery ? _description.text.trim() : null,
            address: role == UserRole.nursery ? _address.text.trim() : null,
            openingHours: role == UserRole.nursery ? _openingHours.text.trim() : null,
            ofstedRating: role == UserRole.nursery ? _ofsted : null,
            bio: role == UserRole.staff ? _bio.text.trim() : null,
            yearsExperience: role == UserRole.staff ? _yearsExperience : null,
            qualificationLevel: role == UserRole.staff ? _qualification : null,
            registeredCompanyName: role == UserRole.nursery ? _registeredCompanyName.text.trim() : null,
            ofstedRegNumber: role == UserRole.nursery ? _ofstedRegNumber.text.trim() : null,
            yearEstablished: role == UserRole.nursery ? (_yearEstablishedValue ?? 0) : null,
            website: role == UserRole.nursery ? _website.text.trim() : null,
            postcode: role == UserRole.nursery ? _postcode.text.trim() : null,
            email: role == UserRole.nursery ? _email.text.trim() : null,
            shortDescription: role == UserRole.nursery ? _shortDescription.text.trim() : null,
            nurseryType: role == UserRole.nursery ? _nurseryType : null,
            facilities: role == UserRole.nursery ? _facilities : null,
            age: role == UserRole.staff ? _age : null,
            city: role == UserRole.staff ? _city.text.trim() : null,
            travelDistanceMiles: role == UserRole.staff ? _travelDistanceMiles : null,
            languages: role == UserRole.staff ? _languages : null,
            professionalSummary: role == UserRole.staff ? _professionalSummary.text.trim() : null,
            qualifications: role == UserRole.staff ? _qualifications : null,
            skills: role == UserRole.staff ? _skills : null,
            availabilityDays: role == UserRole.staff ? _availabilityDays : null,
            availabilityShifts: role == UserRole.staff ? _availabilityShifts : null,
            dbsCertificateNumber: role == UserRole.staff ? _dbsCertificateNumber.text.trim() : null,
            dbsExpiryDate: role == UserRole.staff ? _dbsExpiryDate : null,
            nationality: role == UserRole.staff ? _nationality.text.trim() : null,
            visaStatus: role == UserRole.staff ? _visaStatus : null,
            rightToWorkStatus: role == UserRole.staff ? _rightToWorkStatus : null,
          );
      _initialized = false;
      ref.invalidate(ownProfileProvider);
      if (user != null) {
        ref.invalidate(publicProfileProvider(user.uid));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _sectionHeader(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 8),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(ownProfileProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          _hydrate(profile);
          final isNursery = profile.role == UserRole.nursery;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: scheme.primary.withValues(alpha: 0.12),
                          backgroundImage: _newPhoto != null
                              ? FileImage(_newPhoto!)
                              : (_photoUrl != null ? NetworkImage(_photoUrl!) : null) as ImageProvider?,
                          child: (_newPhoto == null && _photoUrl == null)
                              ? Icon(Icons.person_outline_rounded, size: 40, color: scheme.primary)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppTextField(label: 'Name', controller: _name, prefixIcon: Icons.person_outline_rounded),
                const SizedBox(height: AppSpacing.md),
                PhoneField(
                  controller: _phone,
                  initialDialCode: '+44',
                  onChanged: (full) => setState(() => _fullPhone = full),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _detectLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Detect & update location (GPS)'),
                ),
                const SizedBox(height: AppSpacing.md),
                if (isNursery) ...[
                  AppTextField(
                    label: 'Address',
                    controller: _address,
                    prefixIcon: Icons.place_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  UkPostcodeField(
                    controller: _postcode,
                    onResolved: (details) {
                      if (_address.text.trim().isEmpty && details.district.isNotEmpty) {
                        _address.text = details.district;
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'About nursery',
                    controller: _description,
                    maxLines: 4,
                    prefixIcon: Icons.notes_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Short professional description',
                    controller: _shortDescription,
                    maxLines: 2,
                    prefixIcon: Icons.short_text_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: openingHoursPresets.map((preset) {
                      return ActionChip(
                        label: Text(preset, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => _openingHours.text = preset),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    label: 'Opening hours',
                    controller: _openingHours,
                    prefixIcon: Icons.schedule_outlined,
                  ),

                  _sectionHeader(context, 'Company details'),
                  AppTextField(
                    label: 'Registered company name',
                    controller: _registeredCompanyName,
                    prefixIcon: Icons.business_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Ofsted registration number',
                    controller: _ofstedRegNumber,
                    prefixIcon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _pickYearEstablished,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_yearEstablishedValue == null
                        ? 'Set year established'
                        : 'Established in $_yearEstablishedValue'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Website',
                    controller: _website,
                    prefixIcon: Icons.language_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Contact email',
                    controller: _email,
                    prefixIcon: Icons.email_outlined,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Nursery type', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: nurseryTypeOptions.map((type) {
                      return ChoiceChip(
                        label: Text(nurseryTypeLabel(type)),
                        selected: type == _nurseryType,
                        onSelected: (_) => setState(() => _nurseryType = type),
                      );
                    }).toList(),
                  ),

                  _sectionHeader(context, 'Ofsted rating'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: OfstedRating.values.map((rating) {
                      return ChoiceChip(
                        label: Text(ofstedRatingLabel(rating)),
                        selected: rating == _ofsted,
                        onSelected: (_) => setState(() => _ofsted = rating),
                      );
                    }).toList(),
                  ),

                  _sectionHeader(context, 'Facilities'),
                  ChipMultiSelect(
                    options: nurseryFacilityOptions,
                    selected: _facilities,
                    onChanged: (v) => setState(() => _facilities = v),
                    allowCustom: true,
                  ),

                  _sectionHeader(context, 'Nursery photos gallery'),
                  if (_photos.isNotEmpty)
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Image.network(_photos[i], width: 120, height: 100, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _photos.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: (_loading || _photos.length >= _maxNurseryPhotos) ? null : _addNurseryPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(_photos.length >= _maxNurseryPhotos
                        ? 'Maximum $_maxNurseryPhotos photos reached'
                        : 'Add nursery photo (${_photos.length}/$_maxNurseryPhotos)'),
                  ),
                ] else ...[
                  LabeledAutocompleteField(
                    label: 'City',
                    controller: _city,
                    options: ukCities,
                    prefixIcon: Icons.location_city_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Age (optional)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  NumberStepper(
                    value: _age ?? 0,
                    min: 0,
                    max: 80,
                    onChanged: (v) => setState(() => _age = v == 0 ? null : v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(label: 'About me', controller: _bio, maxLines: 3),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Professional summary',
                    controller: _professionalSummary,
                    maxLines: 3,
                    prefixIcon: Icons.description_outlined,
                  ),

                  _sectionHeader(context, 'Distance willing to travel'),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _travelDistanceMiles.toDouble(),
                          min: 1,
                          max: 50,
                          divisions: 49,
                          label: '$_travelDistanceMiles mi',
                          onChanged: (v) => setState(() => _travelDistanceMiles = v.round()),
                        ),
                      ),
                      SizedBox(width: 56, child: Text('$_travelDistanceMiles mi', textAlign: TextAlign.end)),
                    ],
                  ),

                  _sectionHeader(context, 'Languages spoken'),
                  ChipMultiSelect(
                    options: commonLanguageOptions,
                    selected: _languages,
                    onChanged: (v) => setState(() => _languages = v),
                    allowCustom: true,
                  ),

                  _sectionHeader(context, 'Years of experience'),
                  NumberStepper(
                    value: _yearsExperience,
                    max: 60,
                    suffix: _yearsExperience == 1 ? 'year' : 'years',
                    onChanged: (v) => setState(() => _yearsExperience = v),
                  ),

                  _sectionHeader(context, 'Qualification level'),
                  Wrap(
                    spacing: 8,
                    children: QualificationLevel.values.map((level) {
                      return ChoiceChip(
                        label: Text(qualificationLevelLabel(level)),
                        selected: level == _qualification,
                        onSelected: (_) => setState(() => _qualification = level),
                      );
                    }).toList(),
                  ),

                  _sectionHeader(context, 'Qualifications & certifications'),
                  ChipMultiSelect(
                    options: staffQualificationOptions,
                    selected: _qualifications,
                    onChanged: (v) => setState(() => _qualifications = v),
                    allowCustom: true,
                  ),

                  _sectionHeader(context, 'Skills'),
                  ChipMultiSelect(
                    options: staffSkillOptions,
                    selected: _skills,
                    onChanged: (v) => setState(() => _skills = v),
                    allowCustom: true,
                  ),

                  _sectionHeader(context, 'Availability — days'),
                  ChipMultiSelect(
                    options: availabilityDayOptions,
                    selected: _availabilityDays,
                    onChanged: (v) => setState(() => _availabilityDays = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Availability — times', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  ChipMultiSelect(
                    options: availabilityShiftOptions,
                    selected: _availabilityShifts,
                    onChanged: (v) => setState(() => _availabilityShifts = v),
                  ),

                  _sectionHeader(context, 'DBS'),
                  AppTextField(
                    label: 'DBS certificate number',
                    controller: _dbsCertificateNumber,
                    prefixIcon: Icons.verified_user_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _pickDbsExpiryDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_dbsExpiryDate == null
                        ? 'Set DBS expiry date'
                        : 'Expires ${_dbsExpiryDate!.day}/${_dbsExpiryDate!.month}/${_dbsExpiryDate!.year}'),
                  ),

                  _sectionHeader(context, 'Right to work'),
                  LabeledAutocompleteField(
                    label: 'Nationality',
                    controller: _nationality,
                    options: nationalities,
                    prefixIcon: Icons.flag_outlined,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Visa status', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  ChipOrOtherSelect(
                    options: visaStatusOptions,
                    value: _visaStatus,
                    onChanged: (v) => setState(() => _visaStatus = v),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Right to work status', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  ChipOrOtherSelect(
                    options: rightToWorkStatusOptions,
                    value: _rightToWorkStatus,
                    onChanged: (v) => setState(() => _rightToWorkStatus = v),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Save changes',
                  loading: _loading,
                  onPressed: () => _save(profile.role),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
