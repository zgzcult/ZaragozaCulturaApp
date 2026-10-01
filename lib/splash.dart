/// Pantalla de bienvenida animada con el logo de Maña Zaragoza.
///
/// El logo aparece con un ligero zoom y un latido de corazón, después
/// entran el nombre y «ZARAGOZA» (con las letras separándose) y, al terminar,
/// se funde con la pantalla principal. Un toque la salta.
library;

import 'package:flutter/material.dart';

import 'brand.dart';

class SplashScreen extends StatefulWidget {
  /// Pantalla a la que se pasa al terminar.
  final WidgetBuilder next;

  /// Duración total de la animación.
  final Duration duration;

  const SplashScreen({
    super.key,
    required this.next,
    this.duration = const Duration(milliseconds: 2900),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _left = false;

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale = TweenSequence<double>([
    // Entrada: de pequeño a su tamaño, con un pequeño rebote.
    TweenSequenceItem(
      tween: Tween(
        begin: 0.78,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 36,
    ),
    // Latido de corazón: dos pulsaciones suaves.
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.07,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 7,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.07,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 7,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.05,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 6,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 38),
  ]).animate(_controller);
  late final Animation<double> _nameFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.34, 0.58, curve: Curves.easeOut),
  );
  late final Animation<double> _tagline = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.50, 0.82, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _leave();
    });
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Si el usuario pidió reducir las animaciones, la bienvenida es breve.
    if (MediaQuery.disableAnimationsOf(context) && _controller.isAnimating) {
      _controller.animateTo(1.0, duration: const Duration(milliseconds: 500));
    }
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, _, __) => widget.next(context),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _leave,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _logoFade.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Image.asset(
                        'assets/brand/logo.png',
                        width: 210,
                        filterQuality: FilterQuality.high,
                        semanticLabel: Brand.name,
                        errorBuilder: (_, _, _) =>
                            const SizedBox(width: 210, height: 214),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: _nameFade.value,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - _nameFade.value)),
                      child: const Text(
                        'Maña',
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 46,
                          height: 1.0,
                          fontWeight: FontWeight.w700,
                          color: Brand.navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: _tagline.value,
                    child: Text(
                      'ZARAGOZA',
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        // Las letras se van separando mientras aparece.
                        letterSpacing: 2 + 7 * _tagline.value,
                        color: Brand.navy,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
