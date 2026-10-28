/// Account data exchanged with the backend's /api/v1/auth and /api/v1/me.
library;

enum Gender {
  male('male', 'Male'),
  female('female', 'Female'),
  other('other', 'Other'),
  preferNotToSay('prefer_not_to_say', 'Prefer not to say');

  const Gender(this.wire, this.label);
  final String wire;
  final String label;

  static Gender? fromWire(String? v) => values.where((g) => g.wire == v).firstOrNull;
}

/// Levels follow the WHO ICD-11 categories of distance vision impairment.
enum EyesightLevel {
  none('none', 'No vision impairment', 'Can see well, with or without glasses'),
  mild('mild', 'Mild vision impairment', 'Vision worse than 6/12'),
  moderate('moderate', 'Moderate vision impairment', 'Vision worse than 6/18'),
  severe('severe', 'Severe vision impairment', 'Vision worse than 6/60'),
  blind('blind', 'Blind', 'Vision worse than 3/60'),
  lightPerception('light_perception', 'Blind, light perception only', 'Can tell light from dark'),
  total('total', 'Totally blind', 'No light perception'),
  preferNotToSay('prefer_not_to_say', 'Prefer not to say', '');

  const EyesightLevel(this.wire, this.label, this.detail);
  final String wire;
  final String label;
  final String detail;

  static EyesightLevel? fromWire(String? v) => values.where((e) => e.wire == v).firstOrNull;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.nic,
    this.birthday,
    this.age,
    this.gender,
    this.addressLine1,
    this.addressLine2,
    this.addressLine3,
    this.postalCode,
    this.mobile,
    this.whatsapp,
    this.whatsappSameAsMobile = false,
    this.bmi,
    this.eyesight,
    this.hasPassword = true,
    this.googleLinked = false,
    this.profileComplete = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        email: j['email'] as String,
        firstName: j['first_name'] as String? ?? '',
        lastName: j['last_name'] as String? ?? '',
        nic: j['nic'] as String?,
        birthday: _date(j['birthday']),
        age: j['age'] as int?,
        gender: Gender.fromWire(j['gender'] as String?),
        addressLine1: j['address_line1'] as String?,
        addressLine2: j['address_line2'] as String?,
        addressLine3: j['address_line3'] as String?,
        postalCode: j['postal_code'] as String?,
        mobile: j['mobile'] as String?,
        whatsapp: j['whatsapp'] as String?,
        whatsappSameAsMobile: j['whatsapp_same_as_mobile'] as bool? ?? false,
        bmi: (j['bmi'] as num?)?.toDouble(),
        eyesight: EyesightLevel.fromWire(j['eyesight'] as String?),
        hasPassword: j['has_password'] as bool? ?? true,
        googleLinked: j['google_linked'] as bool? ?? false,
        profileComplete: j['profile_complete'] as bool? ?? true,
      );

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String? nic;
  final DateTime? birthday;
  final int? age;
  final Gender? gender;
  final String? addressLine1;
  final String? addressLine2;
  final String? addressLine3;
  final String? postalCode;
  final String? mobile;
  final String? whatsapp;
  final bool whatsappSameAsMobile;
  final double? bmi;
  final EyesightLevel? eyesight;
  final bool hasPassword;
  final bool googleLinked;

  /// False for a new Google account until the remaining details are saved.
  final bool profileComplete;

  String get fullName => '$firstName $lastName'.trim();

  /// Same keys as the server's response, so a cached copy can be re-read.
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'nic': nic,
        'birthday': birthday == null ? null : isoDate(birthday!),
        'age': age,
        'gender': gender?.wire,
        'address_line1': addressLine1,
        'address_line2': addressLine2,
        'address_line3': addressLine3,
        'postal_code': postalCode,
        'mobile': mobile,
        'whatsapp': whatsapp,
        'whatsapp_same_as_mobile': whatsappSameAsMobile,
        'bmi': bmi,
        'eyesight': eyesight?.wire,
        'has_password': hasPassword,
        'google_linked': googleLinked,
        'profile_complete': profileComplete,
      };
}

/// The personal details a user fills in. Sent to /auth/register (with email
/// and password) and to PUT /me.
class ProfileDraft {
  const ProfileDraft({
    required this.firstName,
    required this.lastName,
    required this.nic,
    required this.birthday,
    required this.gender,
    required this.addressLine1,
    this.addressLine2,
    this.addressLine3,
    required this.postalCode,
    required this.mobile,
    this.whatsappSameAsMobile = false,
    this.whatsapp,
    this.bmi,
    this.eyesight,
  });

  final String firstName;
  final String lastName;
  final String nic;
  final DateTime? birthday;
  final Gender? gender;
  final String addressLine1;
  final String? addressLine2;
  final String? addressLine3;
  final String postalCode;
  final String mobile;
  final bool whatsappSameAsMobile;
  final String? whatsapp;
  final double? bmi;
  final EyesightLevel? eyesight;

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'nic': nic,
        if (birthday != null) 'birthday': isoDate(birthday!),
        if (gender != null) 'gender': gender!.wire,
        'address_line1': addressLine1,
        'address_line2': addressLine2,
        'address_line3': addressLine3,
        'postal_code': postalCode,
        'mobile': mobile,
        'whatsapp_same_as_mobile': whatsappSameAsMobile,
        'whatsapp': whatsappSameAsMobile ? null : whatsapp,
        'bmi': bmi,
        'eyesight': eyesight?.wire,
      };
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
    required this.isNewUser,
  });

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresIn: Duration(seconds: j['expires_in'] as int),
        user: UserProfile.fromJson(j['user'] as Map<String, dynamic>),
        isNewUser: j['is_new_user'] as bool? ?? false,
      );

  final String accessToken;
  final String refreshToken;
  final Duration expiresIn;
  final UserProfile user;
  final bool isNewUser;
}

/// A personal item as stored on the server for the signed-in user.
class RemoteItem {
  const RemoteItem({required this.id, required this.name, required this.label, required this.photoCount,
      required this.createdAt});

  factory RemoteItem.fromJson(Map<String, dynamic> j) => RemoteItem(
        id: j['id'] as String,
        name: j['name'] as String,
        label: j['label'] as String,
        photoCount: j['photo_count'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  final String id;
  final String name;
  final String label;
  final int photoCount;
  final DateTime createdAt;
}
