/// Envío de sugerencias de mejora al servidor, que las guarda y las reenvía
/// por correo con el asunto «Mejora».
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Dirección del servidor que recibe los envíos.
const String _submitUrl = 'https://zaragoza-cultura-app.onrender.com/submit';

enum SubmitResult { ok, rateLimited, invalid, unavailable }

/// Envío de mensajes al servidor. Se puede sustituir en los tests.
abstract class SubmissionClient {
  const SubmissionClient();

  Future<SubmitResult> send({
    required String type,
    required String title,
    required String description,
    String contact = '',
  });
}

class HttpSubmissionClient extends SubmissionClient {
  const HttpSubmissionClient();

  @override
  Future<SubmitResult> send({
    required String type,
    required String title,
    required String description,
    String contact = '',
  }) async {
    try {
      // El servidor gratuito puede tardar en despertar: margen de 60 s.
      final response = await http
          .post(
            Uri.parse(_submitUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': type,
              'title': title,
              'description': description,
              'contact': contact,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return SubmitResult.ok;
      if (response.statusCode == 429) return SubmitResult.rateLimited;
      if ({400, 413, 422}.contains(response.statusCode)) {
        return SubmitResult.invalid;
      }
      return SubmitResult.unavailable;
    } catch (_) {
      return SubmitResult.unavailable;
    }
  }
}

/// Formulario para proponer una mejora: título y descripción.
class SuggestionScreen extends StatefulWidget {
  final SubmissionClient client;

  const SuggestionScreen({
    super.key,
    this.client = const HttpSubmissionClient(),
  });

  @override
  State<SuggestionScreen> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _contact = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    final result = await widget.client.send(
      type: 'mejora',
      title: _title.text.trim(),
      description: _description.text.trim(),
      contact: _contact.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result) {
      case SubmitResult.ok:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('¡Gracias! Hemos recibido tu sugerencia.'),
          ),
        );
        navigator.pop();
      case SubmitResult.rateLimited:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Has enviado varios mensajes seguidos. Inténtalo más tarde.',
            ),
          ),
        );
      case SubmitResult.invalid:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo enviar. Revisa el título y la descripción.',
            ),
          ),
        );
      case SubmitResult.unavailable:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo enviar. Comprueba tu conexión e inténtalo de nuevo.',
            ),
          ),
        );
    }
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E5EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E5EC)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      appBar: AppBar(title: const Text('Sugerir mejoras')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Qué mejorarías de la app? Cuéntanoslo con tus palabras.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF425B71),
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _title,
                  enabled: !_sending,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration('Título de la mejora'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'Escribe un título (mínimo 3 letras).'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  enabled: !_sending,
                  maxLength: 2000,
                  minLines: 6,
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  decoration: _decoration(
                    'Descripción',
                    hint: 'Explica qué cambiarías y por qué te ayudaría.',
                  ),
                  validator: (value) => (value ?? '').trim().length < 10
                      ? 'Cuéntanos un poco más (mínimo 10 letras).'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _contact,
                  enabled: !_sending,
                  maxLength: 200,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _decoration(
                    'Tu correo (opcional)',
                    hint: 'Solo si quieres que te respondamos',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tu mensaje se envía a nuestro servidor y nos llega por correo. '
                  'Si escribes tu correo, solo lo usaremos para responderte.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFF738196),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF1E5F74),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(_sending ? 'Enviando…' : 'Enviar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
