import 'package:flutter/material.dart';

/// A reusable scaffold body wrapper that ensures content is scrollable
/// and constrained to a reasonable max width while centering on wide screens.
class ResponsiveScaffoldBody extends StatelessWidget {
  final Widget child;
  final double maxContentWidth;
  final EdgeInsetsGeometry padding;
  final bool centerVertically;

  const ResponsiveScaffoldBody({
    Key? key,
    required this.child,
    this.maxContentWidth = 560,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    this.centerVertically = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: padding,
            child: Container(
              alignment:
                  centerVertically ? Alignment.center : Alignment.topCenter,
              constraints: centerVertically
                  ? BoxConstraints(minHeight: constraints.maxHeight)
                  : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxContentWidth,
                ),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}


