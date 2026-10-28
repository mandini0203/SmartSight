import 'dart:convert';

import 'package:http/http.dart' as http;

/// Server responses shaped like backend/app/schemas/accounts.py.
Map<String, dynamic> userJson({
  String id = 'u1',
  String email = 'nimal@example.com',
  String first = 'Nimal',
  String last = 'Perera',
  bool complete = true,
  bool hasPassword = true,
  bool google = false,
}) =>
    {
      'id': id,
      'email': email,
      'first_name': first,
      'last_name': last,
      'nic': complete ? '199812300001' : null,
      'birthday': complete ? '1998-05-02' : null,
      'age': complete ? 28 : null,
      'gender': complete ? 'male' : null,
      'address_line1': complete ? '12 Galle Road' : null,
      'address_line2': null,
      'address_line3': complete ? 'Colombo' : null,
      'postal_code': complete ? '00400' : null,
      'mobile': complete ? '+94771234567' : null,
      'whatsapp': complete ? '+94771234567' : null,
      'whatsapp_same_as_mobile': complete,
      'bmi': null,
      'eyesight': complete ? 'severe' : null,
      'has_password': hasPassword,
      'google_linked': google,
      'profile_complete': complete,
      'created_at': '2026-10-22T10:00:00',
    };

int _tokenSeq = 0;

http.Response sessionResponse({Map<String, dynamic>? user, bool isNew = false, int expiresIn = 1800, int status = 200}) {
  _tokenSeq++;
  return http.Response(
    jsonEncode({
      'access_token': 'access-$_tokenSeq',
      'refresh_token': 'refresh-token-number-$_tokenSeq-abcdefghijklmnop',
      'token_type': 'bearer',
      'expires_in': expiresIn,
      'user': user ?? userJson(),
      'is_new_user': isNew,
    }),
    status,
    headers: {'content-type': 'application/json'},
  );
}

http.Response errorResponse(int status, String code, String message) => http.Response(
      jsonEncode({'error': {'code': code, 'message': message, 'details': null}, 'request_id': 'test'}),
      status,
      headers: {'content-type': 'application/json'},
    );
