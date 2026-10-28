import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_dependencies.dart';
import '../voice_input.dart';

/// A large text field with a microphone button that fills it by speech.
///
/// [fromSpeech] turns the recognised words into the field's value, for
/// example "john dot perera at gmail dot com" into an email address.
class VoiceTextField extends StatefulWidget {
  const VoiceTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.fromSpeech,
    this.hint,
    this.helper,
    this.errorText,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.autofillHints,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final String Function(String spoken) fromSpeech;
  final String? hint;
  final String? helper;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  /// Password field: hidden text with a show/hide button, and the spoken
  /// value is never read back.
  final bool obscure;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField> {
  bool _hidden = true;
  bool _listening = false;

  Future<void> _speak() async {
    final deps = AppScope.of(context);
    setState(() => _listening = true);
    final heard = await askByVoice(deps, 'Say your ${widget.label.toLowerCase()}.', private: widget.obscure);
    if (!mounted) return;
    setState(() => _listening = false);
    if (heard == null) {
      await deps.guidance.announce("I didn't hear anything.", remember: false);
      return;
    }
    final value = widget.fromSpeech(heard);
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    await deps.guidance.announce(
      widget.obscure
          ? '${widget.label} entered, ${value.length} characters.'
          : '${widget.label}: ${value.isEmpty ? 'nothing recognised' : value}.',
      remember: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = widget.obscure && _hidden;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: widget.controller,
        readOnly: widget.readOnly,
        obscureText: hidden,
        enableSuggestions: !widget.obscure,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        inputFormatters: widget.inputFormatters,
        onSubmitted: widget.onSubmitted,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          helperText: widget.helper,
          helperMaxLines: 3,
          errorText: widget.errorText,
          errorMaxLines: 3,
          suffixIcon: widget.readOnly
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.obscure)
                      IconButton(
                        tooltip: hidden ? 'Show password' : 'Hide password',
                        icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _hidden = !_hidden),
                      ),
                    IconButton(
                      tooltip: 'Speak ${widget.label.toLowerCase()}',
                      icon: Icon(_listening ? Icons.hearing : Icons.mic),
                      onPressed: _listening ? null : _speak,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
