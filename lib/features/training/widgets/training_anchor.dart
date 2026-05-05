import 'package:flutter/widgets.dart';

class TrainingAnchorRegistry {
  TrainingAnchorRegistry._();

  static final TrainingAnchorRegistry instance = TrainingAnchorRegistry._();

  final Map<String, GlobalKey> _anchors = <String, GlobalKey>{};

  void register(String id, GlobalKey key) {
    _anchors[id] = key;
  }

  void unregister(String id, GlobalKey key) {
    if (_anchors[id] == key) {
      _anchors.remove(id);
    }
  }

  Rect? rectFor(String id) {
    final key = _anchors[id];
    final context = key?.currentContext;
    if (context == null) {
      return null;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return null;
    }

    final offset = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    if (size.isEmpty) {
      return null;
    }

    return offset & size;
  }
}

class TrainingAnchor extends StatefulWidget {
  final String id;
  final Widget child;

  const TrainingAnchor({
    required this.id,
    required this.child,
    super.key,
  });

  @override
  State<TrainingAnchor> createState() => _TrainingAnchorState();
}

class _TrainingAnchorState extends State<TrainingAnchor> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    TrainingAnchorRegistry.instance.register(widget.id, _anchorKey);
  }

  @override
  void didUpdateWidget(covariant TrainingAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      TrainingAnchorRegistry.instance.unregister(oldWidget.id, _anchorKey);
      TrainingAnchorRegistry.instance.register(widget.id, _anchorKey);
    }
  }

  @override
  void dispose() {
    TrainingAnchorRegistry.instance.unregister(widget.id, _anchorKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _anchorKey, child: widget.child);
  }
}
