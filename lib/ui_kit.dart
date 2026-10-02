/// Piezas de interfaz reutilizables: corazón de favorito animado y
/// esqueletos de carga con brillo.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

// ---------------------------------------------------------------------------
// Corazón de favorito
// ---------------------------------------------------------------------------

/// Vibración ligera que acompaña a guardar o quitar un favorito.
void favoriteHaptic() => HapticFeedback.lightImpact();

/// Icono de corazón que «late» (crece y vuelve) cada vez que cambia de estado.
class AnimatedHeartIcon extends StatefulWidget {
  final bool isFavorite;
  final double size;
  final Color idleColor;

  const AnimatedHeartIcon({
    super.key,
    required this.isFavorite,
    this.size = 22,
    this.idleColor = Brand.slate,
  });

  @override
  State<AnimatedHeartIcon> createState() => _AnimatedHeartIconState();
}

class _AnimatedHeartIconState extends State<AnimatedHeartIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.35,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.35,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(AnimatedHeartIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(
        widget.isFavorite ? Icons.favorite : Icons.favorite_border,
        size: widget.size,
        color: widget.isFavorite ? Brand.coral : widget.idleColor,
      ),
    );
  }
}

/// Botón redondo de favorito para poner sobre fotos: late al pulsarlo y el
/// teléfono vibra ligeramente.
class FavoriteHeart extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onPressed;

  const FavoriteHeart({
    super.key,
    required this.isFavorite,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: isFavorite,
      label: isFavorite ? 'Quitar de favoritos' : 'Guardar como favorito',
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.95),
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x330B2D4A),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            favoriteHaptic();
            onPressed();
          },
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: AnimatedHeartIcon(
              isFavorite: isFavorite,
              idleColor: Brand.navy,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Esqueletos de carga
// ---------------------------------------------------------------------------

/// Hace brillar suavemente su contenido (formas grises) mientras se carga.
/// Si el usuario pidió reducir las animaciones, se queda quieto.
class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.0 + 2.6 * t - 0.6, -0.3),
            end: Alignment(-1.0 + 2.6 * t + 0.6, 0.3),
            colors: const [
              Color(0xFFE9E6DA),
              Color(0xFFF6F4EC),
              Color(0xFFE9E6DA),
            ],
            stops: const [0.2, 0.5, 0.8],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Bloque gris redondeado para componer esqueletos.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9E6DA),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Esqueleto de una tarjeta de actividad: imagen, título y dos líneas.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 190, radius: 0),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 220, height: 14),
                SizedBox(height: 12),
                SkeletonBox(width: 160, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista de esqueletos que ocupa el lugar de los resultados mientras cargan.
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 3,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando',
      child: Shimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          children: [for (var i = 0; i < count; i++) const SkeletonCard()],
        ),
      ),
    );
  }
}
