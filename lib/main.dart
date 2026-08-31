import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const PainSketcherApp());
}

class PainSketcherApp extends StatelessWidget {
  const PainSketcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pain Sketcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const BodyChartSelectionPage(),
    );
  }
}

class BodyChartSelectionPage extends StatelessWidget {
  const BodyChartSelectionPage({super.key});

  final List<Map<String, String>> charts = const [
    {
      'name': 'Male Dorsal',
      'path': 'assets/male_dorsal_paper.png',
      'maskPath': 'assets/male_dorsal_mask.png'
    },
    {
      'name': 'Male Ventral',
      'path': 'assets/male_ventral_paper.png',
      'maskPath': 'assets/male_ventral_mask.png'
    },
    {
      'name': 'Female Dorsal',
      'path': 'assets/female_dorsal_paper.png',
      'maskPath': 'assets/female_dorsal_mask.png'
    },
    {
      'name': 'Female Ventral',
      'path': 'assets/female_ventral_paper.png',
      'maskPath': 'assets/female_ventral_mask.png'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Body Chart'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.7,
          ),
          itemCount: charts.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PainDrawingPage(
                      imagePath: charts[index]['path']!,
                      maskPath: charts[index]['maskPath']!,
                      title: charts[index]['name']!,
                    ),
                  ),
                );
              },
              child: Card(
                clipBehavior: Clip.antiAlias,
                elevation: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Image.asset(charts[index]['path']!, fit: BoxFit.contain)),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(charts[index]['name']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class PainPoint {
  final Offset position;
  final double strokeWidth;

  PainPoint(this.position, this.strokeWidth);
}

class PainDrawingPage extends StatefulWidget {
  final String imagePath;
  final String maskPath;
  final String title;

  const PainDrawingPage({
    super.key,
    required this.imagePath,
    required this.maskPath,
    required this.title,
  });

  @override
  State<PainDrawingPage> createState() => _PainDrawingPageState();
}

class _PainDrawingPageState extends State<PainDrawingPage> {
  final List<PainPoint?> _points = [];
  Matrix4 _matrix = Matrix4.identity();
  bool _isDrawing = false;
  double _prevScale = 1.0;
  int _pointers = 0;
  DateTime? _firstPointerStartTime;
  bool _ignoreUntilAllUp = false;

  // GlobalKey to identify the image and its position
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _resetView();
  }

  void _resetView() {
    _matrix = Matrix4.identity()..scale(4.0);
    _prevScale = 1.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final RenderBox? imageBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageBox == null) return;

      final double screenWidth = MediaQuery.sizeOf(context).width;
      final Offset globalTopLeft = imageBox.localToGlobal(Offset.zero);
      final double imageWidth = imageBox.size.width * 4.0;

      setState(() {
        // Centra orizzontalmente: (Schermo - Immagine) / 2
        double dx = (screenWidth - imageWidth) / 2 - globalTopLeft.dx;
        // Allinea al bordo superiore: porta il top a 0
        double dy = -globalTopLeft.dy;

        _matrix = Matrix4.translationValues(dx, dy, 0)..multiply(_matrix);
      });
    });
  }

  void _clearCanvas() {
    setState(() {
      _points.clear();
      _resetView();
    });
  }

  void _performUndo() {
    while (_points.isNotEmpty && _points.last == null) {
      _points.removeLast();
    }
    while (_points.isNotEmpty && _points.last != null) {
      _points.removeLast();
    }
    if (_points.isNotEmpty && _points.last != null) {
      _points.add(null);
    }
  }

  void _undoLastStroke() {
    if (_points.isEmpty) return;
    setState(() => _performUndo());
  }

  void _endStroke() {
    if (_isDrawing) {
      setState(() {
        _isDrawing = false;
        if (_points.isNotEmpty && _points.last != null) {
          _points.add(null);
        }
      });
    }
  }

  Future<Uint8List?> _generatePngBytes() async {
    final RenderBox? imageBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox == null) return null;

    final data = await rootBundle.load(widget.imagePath);
    final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ui.Image background = fi.image;

    const double realWidth = 2304.0;
    const double realHeight = 3072.0;

    // 1. Calculate Pain Extent by comparing with mask
    int totalMaskPixels = 0;
    int painPixelsInMask = 0;

    final double outputScale = realWidth / imageBox.size.width;

    // Render pain strokes to a separate image to count pixels
    final painRecorder = ui.PictureRecorder();
    final painCanvas = Canvas(painRecorder, Rect.fromLTWH(0, 0, realWidth, realHeight));
    final painPaint = Paint()..color = Colors.red..strokeCap = StrokeCap.round;

    for (int i = 0; i < _points.length - 1; i++) {
      final p1 = _points[i];
      final p2 = _points[i + 1];
      if (p1 != null && p2 != null) {
        painPaint.strokeWidth = p1.strokeWidth * outputScale;
        painPaint.style = PaintingStyle.stroke;
        painCanvas.drawLine(p1.position * outputScale, p2.position * outputScale, painPaint);
      } else if (p1 != null && p2 == null) {
        painPaint.style = PaintingStyle.fill;
        painCanvas.drawCircle(p1.position * outputScale, (p1.strokeWidth * outputScale) / 2, painPaint);
      }
    }
    
    final painImg = await painRecorder.endRecording().toImage(realWidth.toInt(), realHeight.toInt());
    final painData = await painImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    
    final maskImg = await _loadAssetImage(widget.maskPath);
    final maskData = await maskImg.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (painData != null && maskData != null) {
      final Uint8List painBytes = painData.buffer.asUint8List();
      final Uint8List maskBytes = maskData.buffer.asUint8List();
      
      for (int i = 0; i < maskBytes.length; i += 4) {
        // format is RGBA, so index + 3 is alpha
        final int maskAlpha = maskBytes[i + 3];
        final int painAlpha = painBytes[i + 3];
        
        if (maskAlpha < 128) { // Pixel inside the body silhouette
          totalMaskPixels++;
          if (painAlpha > 128) { // Pixel marked as pain
            painPixelsInMask++;
          }
        }
      }
    }

    double percentage = totalMaskPixels > 0 ? (painPixelsInMask / totalMaskPixels) * 100 : 0.0;

    // 2. Compose final image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, realWidth, realHeight));

    paintImage(
      canvas: canvas,
      rect: const Rect.fromLTWH(0, 0, realWidth, realHeight),
      image: background,
      fit: BoxFit.contain,
    );

    // Draw pain on final image
    final finalPaint = Paint()..color = Colors.red..strokeCap = StrokeCap.round;
    for (int i = 0; i < _points.length - 1; i++) {
      final p1 = _points[i];
      final p2 = _points[i + 1];
      if (p1 != null && p2 != null) {
        finalPaint.strokeWidth = p1.strokeWidth * outputScale;
        finalPaint.style = PaintingStyle.stroke;
        canvas.drawLine(p1.position * outputScale, p2.position * outputScale, finalPaint);
      } else if (p1 != null && p2 == null) {
        finalPaint.style = PaintingStyle.fill;
        canvas.drawCircle(p1.position * outputScale, (p1.strokeWidth * outputScale) / 2, finalPaint);
      }
    }

    // Add Markers
    final markerTL = await _loadAssetImage('assets/aruco_99.png');
    final markerTR = await _loadAssetImage('assets/aruco_123.png');
    final markerBR = await _loadAssetImage('assets/aruco_432.png');
    final markerBL = await _loadAssetImage('assets/aruco_567.png');

    const double markerSize = 150.0;
    paintImage(canvas: canvas, rect: const Rect.fromLTWH(10, 10, markerSize, markerSize), image: markerTL, fit: BoxFit.fill);
    paintImage(canvas: canvas, rect: Rect.fromLTWH(realWidth - markerSize - 10, 10, markerSize, markerSize), image: markerTR, fit: BoxFit.fill);
    paintImage(canvas: canvas, rect: Rect.fromLTWH(realWidth - markerSize - 10, realHeight - markerSize - 10, markerSize, markerSize), image: markerBR, fit: BoxFit.fill);
    paintImage(canvas: canvas, rect: Rect.fromLTWH(10, realHeight - markerSize - 10, markerSize, markerSize), image: markerBL, fit: BoxFit.fill);

    // Add Pain Extent Text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Pain extent = ${percentage.toStringAsFixed(2)}% ($painPixelsInMask pixel)',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 60,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (realWidth - textPainter.width) / 2,
        realHeight - markerSize - 20, // Centered between markers, slightly above
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(realWidth.toInt(), realHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveToDownloads() async {
    final pngBytes = await _generatePngBytes();
    if (pngBytes == null) return;

    try {
      String? path;
      if (Platform.isAndroid) {
        path = '/storage/emulated/0/Download/pain_sketch_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(path);
        await file.writeAsBytes(pngBytes);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/pain_sketch_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(path);
        await file.writeAsBytes(pngBytes);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads: $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied. Use Share instead.')),
        );
      }
      _shareImage();
    }
  }

  Future<void> _shareImage() async {
    final pngBytes = await _generatePngBytes();
    if (pngBytes == null) return;

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/pain_sketch.png');
    await file.writeAsBytes(pngBytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Pain Sketch');
  }

  Future<ui.Image> _loadAssetImage(String path) async {
    final data = await rootBundle.load(path);

    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    );

    final frame = await codec.getNextFrame();

    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearCanvas,
            tooltip: 'Clear',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveToDownloads,
            tooltip: 'Save to Downloads',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareImage,
            tooltip: 'Share Image',
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoLastStroke,
            tooltip: 'Undo',
          ),
        ],
      ),
      body: ClipRect(
        child: Listener(
          onPointerDown: (event) {
            _pointers++;
            if (_pointers == 1) _firstPointerStartTime = DateTime.now();
            else if (_pointers > 1) {
              _ignoreUntilAllUp = true;
              if (_isDrawing) {
                final elapsed = DateTime.now().difference(_firstPointerStartTime!);
                setState(() {
                  if (elapsed < const Duration(milliseconds: 200)) _performUndo();
                  _endStroke();
                });
              }
            }
          },
          onPointerUp: (event) {
            _pointers--;
            if (_pointers == 0) { _ignoreUntilAllUp = false; _endStroke(); }
          },
          child: GestureDetector(
            onScaleStart: (details) {
              if (_pointers == 1 && !_ignoreUntilAllUp) {
                _isDrawing = true;
                _addPoint(details.focalPoint);
              } else {
                _isDrawing = false;
                _prevScale = 1.0;
              }
            },
            onScaleUpdate: (details) {
              if (_pointers == 1 && _isDrawing && !_ignoreUntilAllUp) {
                _addPoint(details.focalPoint);
              } else if (_pointers >= 2) {
                setState(() {
                  final translation = details.focalPointDelta;
                  _matrix = Matrix4.translationValues(translation.dx, translation.dy, 0)..multiply(_matrix);
                  if (details.scale != 1.0) {
                    final double deltaScale = details.scale / _prevScale;
                    _prevScale = details.scale;
                    final focalPoint = details.localFocalPoint;
                    final currentScale = _matrix.getMaxScaleOnAxis();
                    
                    // Fixed Matrix4 transformations
                    if ((currentScale > 1.0 || deltaScale > 1.0) && (currentScale < 16.0 || deltaScale < 1.0)) {
                      _matrix = Matrix4.identity()
                        ..translate(focalPoint.dx, focalPoint.dy)
                        ..scale(deltaScale)
                        ..translate(-focalPoint.dx, -focalPoint.dy)
                        ..multiply(_matrix);
                    }
                  }
                });
              }
            },
            onScaleEnd: (details) {
              _endStroke();
              _clampHorizontalPan();
              _clampVerticalPan();
            },


            child: Transform(
              transform: _matrix,
              child: Center(
                child: SizedBox(
                  width: 600,
                  child: AspectRatio(
                    aspectRatio: 2304 / 3072,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          widget.imagePath,
                          key: _imageKey,
                          fit: BoxFit.contain,
                        ),
                        CustomPaint(
                          painter: PainPainter(points: _points),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          ),
        ),
      ),
    );
  }

  void _clampHorizontalPan() {
    final RenderBox? imageBox =
    _imageKey.currentContext?.findRenderObject() as RenderBox?;

    if (imageBox == null) return;

    final double screenWidth = MediaQuery.sizeOf(context).width;

    final double left =
        imageBox.localToGlobal(Offset.zero).dx;

    final double right =
        imageBox.localToGlobal(
          Offset(imageBox.size.width, 0),
        ).dx;

    final double imageWidth = right - left;

    double correction = 0;

    if (imageWidth <= screenWidth) {
      // Se il foglio è più stretto dello schermo:
      // lo teniamo centrato
      correction =
          screenWidth / 2 - (left + right) / 2;
    } else {
      // Impedisce di mostrare spazio vuoto a sinistra
      if (left > 0) {
        correction = -left;
      }

      // Impedisce di mostrare spazio vuoto a destra
      if (right < screenWidth) {
        correction = screenWidth - right;
      }
    }

    if (correction != 0) {
      setState(() {
        _matrix =
        Matrix4.translationValues(correction, 0, 0)
          ..multiply(_matrix);
      });
    }
  }

  void _clampVerticalPan() {
    final RenderBox? imageBox =
    _imageKey.currentContext?.findRenderObject() as RenderBox?;

    if (imageBox == null) return;

    final double screenHeight = MediaQuery.sizeOf(context).height;

    final double top =
        imageBox.localToGlobal(Offset.zero).dy;

    final double bottom =
        imageBox.localToGlobal(
          Offset(0, imageBox.size.height),
        ).dy;

    final double imageHeight = bottom - top;

    double correction = 0;

    if (imageHeight <= screenHeight) {
      // Se tutta l'immagine entra nello schermo,
      // la manteniamo centrata verticalmente.
      correction =
          screenHeight / 2 - (top + bottom) / 2;
    } else {
      // Non lasciare spazio vuoto sopra.
      if (top > 0) {
        correction = -top;
      }

      // Non lasciare spazio vuoto sotto.
      if (bottom < screenHeight) {
        correction = screenHeight - bottom;
      }
    }

    if (correction != 0) {
      setState(() {
        _matrix =
        Matrix4.translationValues(0, correction, 0)
          ..multiply(_matrix);
      });
    }
  }

  void _addPoint(Offset globalFocalPoint) {
    final RenderBox? imageBox =
    _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox == null) return;
    // Da coordinate globali del dito direttamente
    // alle coordinate locali della body chart
    final Offset scenePoint =
    imageBox.globalToLocal(globalFocalPoint);
    final double currentScale = _matrix.getMaxScaleOnAxis();
    setState(() {
      _points.add(
        PainPoint(scenePoint, 30.0 / currentScale),
      );
    });
  }


}

class PainPainter extends CustomPainter {
  final List<PainPoint?> points;
  PainPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()..color = Colors.red..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) {
        paint.strokeWidth = p1.strokeWidth;
        paint.style = PaintingStyle.stroke;
        canvas.drawLine(p1.position, p2.position, paint);
      } else if (p1 != null && p2 == null) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(p1.position, p1.strokeWidth / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PainPainter oldDelegate) => true;
}
