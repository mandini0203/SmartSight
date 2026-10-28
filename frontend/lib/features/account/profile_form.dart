import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_dependencies.dart';
import '../../core/auth/nic.dart';
import '../../core/auth/profile.dart';
import '../../core/voice/form_speech.dart';
import '../../shared/voice_form_filler.dart';
import '../../shared/voice_input.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/voice_text_field.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November',
  'December',
];

String formatDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$', caseSensitive: false);
final _namePattern = RegExp(r"^\p{L}+(?:[ '.\-]\p{L}+)*\.?$", unicode: true);
final _postalPattern = RegExp(r'^\d{5}$');

/// Mirrors the backend's phone rule: local Sri Lankan numbers become +94.
String? normalisePhone(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (s.startsWith('00')) {
    s = '+${s.substring(2)}';
  } else if (RegExp(r'^0\d{9}$').hasMatch(s)) {
    s = '+94${s.substring(1)}';
  } else if (RegExp(r'^94\d{9}$').hasMatch(s)) {
    s = '+$s';
  }
  return RegExp(r'^\+\d{9,15}$').hasMatch(s) ? s : null;
}

/// State of the registration / profile form. Birthday, age and gender are
/// filled in from a valid NIC number.
class ProfileFormController extends ChangeNotifier {
  ProfileFormController({required this.includeAccount, UserProfile? initial}) {
    if (initial != null) _fill(initial);
    nic.addListener(_onNicChanged);
    _onNicChanged();
  }

  /// Registration with email and password (not for Google or profile edits).
  final bool includeAccount;

  final email = TextEditingController();
  final password = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final nic = TextEditingController();
  final addressLine1 = TextEditingController();
  final addressLine2 = TextEditingController();
  final addressLine3 = TextEditingController();
  final postalCode = TextEditingController();
  final mobile = TextEditingController();
  final whatsapp = TextEditingController();
  final bmi = TextEditingController();

  DateTime? birthday;
  Gender? gender;
  EyesightLevel? eyesight;
  bool whatsappSameAsMobile = true;
  NicInfo? nicInfo;

  /// Error per field key, shown under the field.
  Map<String, String> errors = {};

  int? get age => birthday == null ? null : ageOn(birthday!);

  void _fill(UserProfile u) {
    email.text = u.email;
    firstName.text = u.firstName;
    lastName.text = u.lastName;
    nic.text = u.nic ?? '';
    birthday = u.birthday;
    gender = u.gender;
    addressLine1.text = u.addressLine1 ?? '';
    addressLine2.text = u.addressLine2 ?? '';
    addressLine3.text = u.addressLine3 ?? '';
    postalCode.text = u.postalCode ?? '';
    mobile.text = u.mobile ?? '';
    whatsappSameAsMobile = u.whatsapp == null || u.whatsappSameAsMobile;
    whatsapp.text = whatsappSameAsMobile ? '' : u.whatsapp ?? '';
    bmi.text = u.bmi?.toString() ?? '';
    eyesight = u.eyesight;
  }

  void _onNicChanged() {
    final r = decodeNic(nic.text);
    final info = r.info;
    if (info?.nic == nicInfo?.nic) return;
    nicInfo = info;
    if (info != null) {
      birthday = info.birthday;
      // Keep "Other" or "Prefer not to say" if the user chose it.
      if (gender == null || gender == Gender.male || gender == Gender.female) {
        gender = info.gender == NicGender.female ? Gender.female : Gender.male;
      }
      errors.remove('nic');
    }
    notifyListeners();
  }

  void setBirthday(DateTime? d) {
    birthday = d;
    notifyListeners();
  }

  void setGender(Gender? g) {
    gender = g;
    notifyListeners();
  }

  void setEyesight(EyesightLevel? e) {
    eyesight = e;
    notifyListeners();
  }

  void setWhatsappSame(bool same) {
    whatsappSameAsMobile = same;
    notifyListeners();
  }

  /// Checks every field; returns the errors in form order (empty when valid).
  List<String> validate() {
    final e = <String, String>{};
    if (includeAccount) {
      if (!_emailPattern.hasMatch(email.text.trim())) e['email'] = 'Enter a valid email address.';
      final p = password.text;
      if (p.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
        e['password'] = 'Use at least 8 characters, including a letter and a number.';
      }
    }
    for (final (key, c, label) in [('firstName', firstName, 'first name'), ('lastName', lastName, 'last name')]) {
      final v = c.text.trim();
      if (v.isEmpty) {
        e[key] = 'Enter your $label.';
      } else if (!_namePattern.hasMatch(v)) {
        e[key] = 'Your $label can only contain letters, spaces, hyphens and apostrophes.';
      }
    }
    final nicResult = decodeNic(nic.text);
    if (!nicResult.isValid) e['nic'] = nicResult.error!;
    if (birthday == null) e['birthday'] = 'Enter your birthday.';
    if (gender == null) e['gender'] = 'Choose your gender.';
    if (addressLine1.text.trim().isEmpty) e['addressLine1'] = 'Enter the first line of your home address.';
    if (!_postalPattern.hasMatch(postalCode.text.trim())) e['postalCode'] = 'Enter a 5-digit postal code.';
    if (normalisePhone(mobile.text) == null) e['mobile'] = 'Enter a mobile number such as 0771234567.';
    if (!whatsappSameAsMobile && whatsapp.text.trim().isNotEmpty && normalisePhone(whatsapp.text) == null) {
      e['whatsapp'] = 'Enter a WhatsApp number such as 0771234567.';
    }
    if (bmi.text.trim().isNotEmpty) {
      final v = double.tryParse(bmi.text.trim());
      if (v == null || v < 10 || v > 80) e['bmi'] = 'BMI must be a number between 10 and 80.';
    }
    errors = e;
    notifyListeners();
    return e.values.toList();
  }

  ProfileDraft toDraft() => ProfileDraft(
        firstName: firstName.text.trim(),
        lastName: lastName.text.trim(),
        nic: normaliseNic(nic.text),
        birthday: birthday,
        gender: gender,
        addressLine1: addressLine1.text.trim(),
        addressLine2: _orNull(addressLine2.text),
        addressLine3: _orNull(addressLine3.text),
        postalCode: postalCode.text.trim(),
        mobile: normalisePhone(mobile.text) ?? mobile.text.trim(),
        whatsappSameAsMobile: whatsappSameAsMobile,
        whatsapp: whatsappSameAsMobile ? null : _orNull(whatsapp.text),
        bmi: double.tryParse(bmi.text.trim()),
        eyesight: eyesight,
      );

  String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();

  /// Questions for filling the whole form by voice, in form order.
  List<VoiceStep> voiceSteps() {
    String text(TextEditingController c, String label, String value) {
      c.text = value;
      notifyListeners();
      return '$label: ${value.isEmpty ? 'blank' : value}.';
    }

    return [
      if (includeAccount) ...[
        VoiceStep(
          prompt: 'What is your email address? Say it like: john dot perera at gmail dot com.',
          apply: (s) {
            final v = spokenToEmail(s);
            if (!_emailPattern.hasMatch(v)) throw VoiceStepError('I heard $v, which is not a valid email. Please say it again.');
            return text(email, 'Email', v);
          },
        ),
        VoiceStep(
          prompt: 'Choose a password of at least 8 letters and numbers, and say it now.',
          private: true,
          apply: (s) {
            final v = spokenToPassword(s);
            if (v.length < 8 || !RegExp(r'\d').hasMatch(v) || !RegExp(r'[A-Za-z]').hasMatch(v)) {
              throw const VoiceStepError('That password is too short or has no number. Please say another one.');
            }
            password.text = v;
            return 'Password entered, ${v.length} characters.';
          },
        ),
      ],
      VoiceStep(prompt: 'What is your first name?', apply: (s) => text(firstName, 'First name', spokenToName(s))),
      VoiceStep(prompt: 'What is your last name?', apply: (s) => text(lastName, 'Last name', spokenToName(s))),
      VoiceStep(
        prompt: 'What is your NIC number? Say each digit, and the letter V or X at the end if it has one.',
        apply: (s) {
          final v = spokenToNic(s);
          final r = decodeNic(v);
          if (!r.isValid) throw VoiceStepError('I heard ${_spell(v)}. ${r.error} Please say it again.');
          nic.text = r.info!.nic;
          final info = r.info!;
          return 'NIC: ${_spell(info.nic)}. From your NIC, your birthday is ${formatDate(info.birthday)}, '
              'age ${ageOn(info.birthday)}, gender ${info.gender.name}.';
        },
      ),
      VoiceStep(
        prompt: 'What is your date of birth? For example: 12 March 1998.',
        when: () => nicInfo == null,
        apply: (s) {
          final d = parseSpokenDate(s);
          if (d == null || d.isAfter(DateTime.now())) throw const VoiceStepError('I did not understand that date. Please say it again.');
          setBirthday(d);
          return 'Birthday: ${formatDate(d)}.';
        },
      ),
      VoiceStep(
        prompt: 'What is your gender? Male, female, other, or prefer not to say.',
        when: () => nicInfo == null,
        apply: (s) {
          final g = matchGender(s);
          if (g == null) throw const VoiceStepError('Please say male, female, other, or prefer not to say.');
          setGender(g);
          return 'Gender: ${g.label}.';
        },
      ),
      VoiceStep(
        prompt: 'What is the first line of your home address? For example, house number and street.',
        apply: (s) => text(addressLine1, 'Address line 1', spokenToText(s)),
      ),
      VoiceStep(
        prompt: 'What is the second line of your address, such as your area or village?',
        optional: true,
        apply: (s) => text(addressLine2, 'Address line 2', spokenToText(s)),
      ),
      VoiceStep(
        prompt: 'What is the third line of your address, such as your town or city?',
        optional: true,
        apply: (s) => text(addressLine3, 'Address line 3', spokenToText(s)),
      ),
      VoiceStep(
        prompt: 'What is your postal code?',
        apply: (s) {
          final v = spokenToPostalCode(s);
          if (!_postalPattern.hasMatch(v)) throw VoiceStepError('I heard ${_spell(v)}. A postal code has 5 digits. Please say it again.');
          postalCode.text = v;
          notifyListeners();
          return 'Postal code: ${_spell(v)}.';
        },
      ),
      VoiceStep(
        prompt: 'What is your mobile number?',
        apply: (s) {
          final v = spokenToPhone(s);
          if (normalisePhone(v) == null) throw VoiceStepError('I heard ${_spell(v)}, which is not a phone number. Please say it again.');
          mobile.text = v;
          notifyListeners();
          return 'Mobile number: ${_spell(v)}.';
        },
      ),
      VoiceStep(
        prompt: 'Is your WhatsApp number the same as your mobile number? Say yes or no.',
        apply: (s) {
          final yes = matchYesNo(s);
          if (yes == null) throw const VoiceStepError('Please say yes or no.');
          setWhatsappSame(yes);
          return yes ? 'WhatsApp is the same as your mobile.' : 'OK, a different WhatsApp number.';
        },
      ),
      VoiceStep(
        prompt: 'What is your WhatsApp number?',
        optional: true,
        when: () => !whatsappSameAsMobile,
        apply: (s) {
          final v = spokenToPhone(s);
          if (normalisePhone(v) == null) throw VoiceStepError('I heard ${_spell(v)}, which is not a phone number. Please say it again.');
          whatsapp.text = v;
          notifyListeners();
          return 'WhatsApp number: ${_spell(v)}.';
        },
      ),
      VoiceStep(
        prompt: 'What is your body mass index, or BMI? For example, 22 point 5.',
        optional: true,
        apply: (s) {
          final v = spokenToNumber(s);
          if (v == null || v < 10 || v > 80) throw const VoiceStepError('BMI should be a number between 10 and 80. Please say it again, or say skip.');
          return text(bmi, 'BMI', v.toStringAsFixed(1));
        },
      ),
      VoiceStep(
        prompt: 'How is your eyesight? Say: no impairment, mild, moderate, severe, blind, '
            'light perception only, or totally blind.',
        optional: true,
        apply: (s) {
          final level = matchEyesight(s);
          if (level == null) throw const VoiceStepError('Please say mild, moderate, severe, blind, light perception only, or totally blind.');
          setEyesight(level);
          return 'Eyesight: ${level.label}.';
        },
      ),
    ];
  }

  /// "0771234567" -> "0 7 7 1 2 3 4 5 6 7", so speech reads digits one by one.
  static String _spell(String digits) => digits.split('').join(' ');

  @override
  void dispose() {
    for (final c in [email, password, firstName, lastName, nic, addressLine1, addressLine2, addressLine3, postalCode,
        mobile, whatsapp, bmi]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The form fields, grouped into sections. Every field can be typed or
/// spoken with its microphone button.
class ProfileForm extends StatelessWidget {
  const ProfileForm({super.key, required this.controller});

  final ProfileFormController controller;

  Future<void> _pickBirthday(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: controller.birthday ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your birthday',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (d != null) controller.setBirthday(d);
  }

  Future<void> _speakChoice<T>(BuildContext context, String prompt, T? Function(String) match, void Function(T) set,
      String Function(T) label) async {
    final deps = AppScope.of(context);
    final heard = await askByVoice(deps, prompt);
    final value = heard == null ? null : match(heard);
    if (value == null) {
      await deps.guidance.announce("I didn't understand. Please choose from the list.", remember: false);
      return;
    }
    set(value);
    await deps.guidance.announce('${label(value)} selected.', remember: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final e = c.errors;
        final nicInfo = c.nicInfo;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.includeAccount) ...[
              const SectionHeading('Account'),
              VoiceTextField(
                key: const Key('email-field'),
                controller: c.email,
                label: 'Email',
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                errorText: e['email'],
                fromSpeech: spokenToEmail,
              ),
              VoiceTextField(
                key: const Key('password-field'),
                controller: c.password,
                label: 'Password',
                helper: 'At least 8 characters, including a letter and a number.',
                obscure: true,
                autofillHints: const [AutofillHints.newPassword],
                errorText: e['password'],
                fromSpeech: spokenToPassword,
              ),
            ],
            const SectionHeading('Personal details'),
            VoiceTextField(
              key: const Key('first-name-field'),
              controller: c.firstName,
              label: 'First name',
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.givenName],
              errorText: e['firstName'],
              fromSpeech: spokenToName,
            ),
            VoiceTextField(
              key: const Key('last-name-field'),
              controller: c.lastName,
              label: 'Last name',
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.familyName],
              errorText: e['lastName'],
              fromSpeech: spokenToName,
            ),
            VoiceTextField(
              key: const Key('nic-field'),
              controller: c.nic,
              label: 'NIC number',
              hint: '199812345678 or 981234567V',
              helper: 'Your birthday, age and gender are filled in from your NIC.',
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9vVxX]')),
                LengthLimitingTextInputFormatter(12),
              ],
              errorText: e['nic'],
              fromSpeech: spokenToNic,
            ),
            _BirthdayTile(
              birthday: c.birthday,
              age: c.age,
              fromNic: nicInfo != null,
              error: e['birthday'],
              onPick: () => _pickBirthday(context),
            ),
            const SizedBox(height: 8),
            _ChoiceField<Gender>(
              key: const Key('gender-field'),
              label: 'Gender',
              value: c.gender,
              options: Gender.values,
              optionLabel: (g) => g.label,
              helper: nicInfo != null ? 'Filled in from your NIC.' : null,
              error: e['gender'],
              onChanged: c.setGender,
              onSpeak: () => _speakChoice<Gender>(context, 'Say male, female, other, or prefer not to say.',
                  matchGender, c.setGender, (g) => g.label),
            ),
            const SectionHeading('Home address'),
            VoiceTextField(
              key: const Key('address1-field'),
              controller: c.addressLine1,
              label: 'Address line 1',
              hint: 'House number and street',
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.streetAddressLine1],
              errorText: e['addressLine1'],
              fromSpeech: spokenToText,
            ),
            VoiceTextField(
              key: const Key('address2-field'),
              controller: c.addressLine2,
              label: 'Address line 2 (optional)',
              hint: 'Area or village',
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.streetAddressLine2],
              fromSpeech: spokenToText,
            ),
            VoiceTextField(
              key: const Key('address3-field'),
              controller: c.addressLine3,
              label: 'Address line 3 (optional)',
              hint: 'Town or city',
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.addressCity],
              fromSpeech: spokenToText,
            ),
            VoiceTextField(
              key: const Key('postal-code-field'),
              controller: c.postalCode,
              label: 'Postal code',
              hint: 'For example 10115',
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.postalCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              errorText: e['postalCode'],
              fromSpeech: spokenToPostalCode,
            ),
            const SectionHeading('Contact'),
            VoiceTextField(
              key: const Key('mobile-field'),
              controller: c.mobile,
              label: 'Mobile number',
              hint: '0771234567',
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              errorText: e['mobile'],
              fromSpeech: spokenToPhone,
            ),
            CheckboxListTile(
              key: const Key('whatsapp-same-checkbox'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: c.whatsappSameAsMobile,
              onChanged: (v) => c.setWhatsappSame(v ?? true),
              title: const Text('My WhatsApp number is the same as my mobile number', style: TextStyle(fontSize: 18)),
            ),
            if (!c.whatsappSameAsMobile)
              VoiceTextField(
                key: const Key('whatsapp-field'),
                controller: c.whatsapp,
                label: 'WhatsApp number (optional)',
                hint: '0771234567',
                keyboardType: TextInputType.phone,
                errorText: e['whatsapp'],
                fromSpeech: spokenToPhone,
              ),
            const SectionHeading('Health'),
            VoiceTextField(
              key: const Key('bmi-field'),
              controller: c.bmi,
              label: 'BMI (optional)',
              hint: 'For example 22.5',
              helper: 'Body mass index: weight in kilograms divided by height in metres squared.',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              errorText: e['bmi'],
              fromSpeech: (s) => spokenToNumber(s)?.toStringAsFixed(1) ?? '',
            ),
            const SizedBox(height: 6),
            _ChoiceField<EyesightLevel>(
              key: const Key('eyesight-field'),
              label: 'Eyesight (optional)',
              value: c.eyesight,
              options: EyesightLevel.values,
              optionLabel: (l) => l.label,
              optionDetail: (l) => l.detail,
              helper: 'Helps SmartSight give guidance suited to you.',
              onChanged: c.setEyesight,
              onSpeak: () => _speakChoice<EyesightLevel>(
                  context,
                  'How is your eyesight? Say no impairment, mild, moderate, severe, blind, '
                  'light perception only, or totally blind.',
                  matchEyesight,
                  c.setEyesight,
                  (l) => l.label),
            ),
          ],
        );
      },
    );
  }
}

class _BirthdayTile extends StatelessWidget {
  const _BirthdayTile({required this.birthday, required this.age, required this.fromNic, required this.onPick,
      this.error});

  final DateTime? birthday;
  final int? age;
  final bool fromNic;
  final VoidCallback onPick;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = birthday == null ? 'Not set' : '${formatDate(birthday!)} · Age $age';
    return Card(
      key: const Key('birthday-tile'),
      child: ListTile(
        minVerticalPadding: 12,
        leading: const Icon(Icons.cake_outlined, size: 32),
        title: Text('Birthday and age', style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(fromNic ? 'Filled in from your NIC.' : 'Enter your NIC, or choose your birthday.',
                style: const TextStyle(fontSize: 15)),
            if (error != null) Text(error!, style: TextStyle(color: scheme.error, fontSize: 15)),
          ],
        ),
        // Locked to the NIC so the two can never disagree.
        trailing: fromNic ? const Icon(Icons.lock_outline) : TextButton(onPressed: onPick, child: const Text('Choose')),
      ),
    );
  }
}

class _ChoiceField<T> extends StatelessWidget {
  const _ChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    required this.onSpeak,
    this.optionDetail,
    this.helper,
    this.error,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T) optionLabel;
  final String Function(T)? optionDetail;
  final void Function(T) onChanged;
  final VoidCallback onSpeak;
  final String? helper;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<T>(
            initialValue: value,
            key: ValueKey(value),
            isExpanded: true,
            itemHeight: null,
            decoration: InputDecoration(labelText: label, helperText: helper, errorText: error, helperMaxLines: 2),
            selectedItemBuilder: (_) => [
              for (final o in options) Text(optionLabel(o), style: const TextStyle(fontSize: 18), overflow: TextOverflow.ellipsis),
            ],
            items: [
              for (final o in options)
                DropdownMenuItem(
                  value: o,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(optionLabel(o), style: const TextStyle(fontSize: 18)),
                        if (optionDetail != null && optionDetail!(o).isNotEmpty)
                          Text(optionDetail!(o), style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
        IconButton(
          tooltip: 'Speak ${label.toLowerCase()}',
          icon: const Icon(Icons.mic),
          iconSize: 30,
          padding: const EdgeInsets.all(14),
          onPressed: onSpeak,
        ),
      ],
    );
  }
}
