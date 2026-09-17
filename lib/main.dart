import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const FinanzasApp());
}

class FinanzasApp extends StatelessWidget {
  const FinanzasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mis Finanzas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
      ),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// UTILIDADES
// ---------------------------------------------------------------------------

const List<String> _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String nombreMes(int mes) => _meses[mes - 1];

String formatoFecha(DateTime f) => '${f.day} de ${nombreMes(f.month)}';

/// Paleta de colores para diferenciar categorías en las gráficas.
const List<Color> _paleta = [
  Color(0xFF2E7D32), Color(0xFF1565C0), Color(0xFFEF6C00),
  Color(0xFF6A1B9A), Color(0xFFC62828), Color(0xFF00838F),
  Color(0xFFAD1457), Color(0xFF9E9D24), Color(0xFF4E342E),
  Color(0xFF37474F),
];

Color colorPara(int index) => _paleta[index % _paleta.length];

// ---------------------------------------------------------------------------
// MODELOS
// ---------------------------------------------------------------------------

class CategoriaConfig {
  String nombre;
  IconData icono;
  double estimadoMesActual;
  double estimadoProximoMes;

  CategoriaConfig({
    required this.nombre,
    required this.icono,
    this.estimadoMesActual = 0,
    this.estimadoProximoMes = 0,
  });

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'icono': icono.codePoint,
        'estimadoMesActual': estimadoMesActual,
        'estimadoProximoMes': estimadoProximoMes,
      };

  factory CategoriaConfig.fromJson(Map<String, dynamic> json) =>
      CategoriaConfig(
        nombre: json['nombre'],
        icono: IconData(json['icono'], fontFamily: 'MaterialIcons'),
        estimadoMesActual: (json['estimadoMesActual'] as num).toDouble(),
        estimadoProximoMes: (json['estimadoProximoMes'] as num).toDouble(),
      );
}

class Gasto {
  String id;
  String categoria; // nombre de la categoría
  double monto;
  DateTime fecha;
  String nota;

  Gasto({
    required this.id,
    required this.categoria,
    required this.monto,
    required this.fecha,
    this.nota = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoria': categoria,
        'monto': monto,
        'fecha': fecha.toIso8601String(),
        'nota': nota,
      };

  factory Gasto.fromJson(Map<String, dynamic> json) => Gasto(
        id: json['id'],
        categoria: json['categoria'],
        monto: (json['monto'] as num).toDouble(),
        fecha: DateTime.parse(json['fecha']),
        nota: json['nota'] ?? '',
      );
}

List<CategoriaConfig> categoriasPorDefecto() => [
      CategoriaConfig(nombre: 'Comida', icono: Icons.restaurant),
      CategoriaConfig(nombre: 'Transporte', icono: Icons.directions_bus),
      CategoriaConfig(nombre: 'Entretenimiento', icono: Icons.movie),
      CategoriaConfig(
          nombre: 'Artículos de limpieza', icono: Icons.cleaning_services),
      CategoriaConfig(nombre: 'Cuidado personal', icono: Icons.spa),
      CategoriaConfig(nombre: 'Ahorro', icono: Icons.savings),
      CategoriaConfig(nombre: 'Pago de créditos', icono: Icons.credit_card),
      CategoriaConfig(
          nombre: 'Servicios (luz, agua, internet)', icono: Icons.bolt),
      CategoriaConfig(nombre: 'Otros', icono: Icons.category),
    ];

// ---------------------------------------------------------------------------
// PANTALLA PRINCIPAL (con pestañas)
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  List<CategoriaConfig> categorias = [];
  List<Gasto> gastos = [];
  bool cargando = true;
  late TabController _tabController;

  static const _keyCategorias = 'categorias_finanzas_v2';
  static const _keyGastos = 'gastos_finanzas_v1';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();

    final dataCategorias = prefs.getString(_keyCategorias);
    if (dataCategorias != null) {
      final List<dynamic> lista = jsonDecode(dataCategorias);
      categorias = lista.map((e) => CategoriaConfig.fromJson(e)).toList();
    } else {
      categorias = categoriasPorDefecto();
    }

    final dataGastos = prefs.getString(_keyGastos);
    if (dataGastos != null) {
      final List<dynamic> lista = jsonDecode(dataGastos);
      gastos = lista.map((e) => Gasto.fromJson(e)).toList();
    }

    setState(() => cargando = false);
  }

  Future<void> _guardarCategorias() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyCategorias, jsonEncode(categorias.map((c) => c.toJson()).toList()));
  }

  Future<void> _guardarGastos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyGastos, jsonEncode(gastos.map((g) => g.toJson()).toList()));
  }

  // --- Cálculos sobre el mes actual -----------------------------------

  List<Gasto> get gastosMesActual {
    final ahora = DateTime.now();
    return gastos
        .where((g) => g.fecha.year == ahora.year && g.fecha.month == ahora.month)
        .toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
  }

  double gastadoPorCategoria(String nombre) => gastosMesActual
      .where((g) => g.categoria == nombre)
      .fold(0.0, (sum, g) => sum + g.monto);

  double get totalEstimadoMesActual =>
      categorias.fold(0, (sum, c) => sum + c.estimadoMesActual);

  double get totalGastadoMesActual =>
      gastosMesActual.fold(0, (sum, g) => sum + g.monto);

  double get totalEstimadoProximoMes =>
      categorias.fold(0, (sum, c) => sum + c.estimadoProximoMes);

  // --- Acciones ----------------------------------------------------------

  Future<void> _registrarGasto() async {
    if (categorias.isEmpty) return;
    String categoriaSeleccionada = categorias.first.nombre;
    final montoCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    DateTime fecha = DateTime.now();

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Registrar gasto',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: categoriaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: categorias
                        .map((c) => DropdownMenuItem(
                              value: c.nombre,
                              child: Text(c.nombre),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setModalState(() => categoriaSeleccionada = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: montoCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monto gastado',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final seleccionada = await showDatePicker(
                        context: context,
                        initialDate: fecha,
                        firstDate: DateTime(fecha.year - 1),
                        lastDate: DateTime(fecha.year + 1),
                      );
                      if (seleccionada != null) {
                        setModalState(() => fecha = seleccionada);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha del gasto',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(formatoFecha(fecha)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final monto = double.tryParse(montoCtrl.text) ?? 0;
                      if (monto <= 0) return;
                      gastos.add(Gasto(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        categoria: categoriaSeleccionada,
                        monto: monto,
                        fecha: fecha,
                        nota: notaCtrl.text.trim(),
                      ));
                      Navigator.pop(context, true);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Guardar gasto'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (guardado == true) {
      await _guardarGastos();
      setState(() {});
    }
  }

  Future<void> _eliminarGasto(Gasto g) async {
    setState(() => gastos.removeWhere((e) => e.id == g.id));
    await _guardarGastos();
  }

  Future<void> _editarPresupuesto(CategoriaConfig cat, {required bool proximoMes}) async {
    final ctrl = TextEditingController(
      text: (proximoMes ? cat.estimadoProximoMes : cat.estimadoMesActual) == 0
          ? ''
          : (proximoMes ? cat.estimadoProximoMes : cat.estimadoMesActual)
              .toStringAsFixed(2),
    );

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(cat.icono, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cat.nombre,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                proximoMes
                    ? 'Presupuesto planeado para ${nombreMes(DateTime.now().month % 12 + 1)}'
                    : 'Presupuesto de este mes',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Presupuesto estimado',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final valor = double.tryParse(ctrl.text) ?? 0;
                  if (proximoMes) {
                    cat.estimadoProximoMes = valor;
                  } else {
                    cat.estimadoMesActual = valor;
                  }
                  Navigator.pop(context, true);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Guardar'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (guardado == true) {
      await _guardarCategorias();
      setState(() {});
    }
  }

  void _agregarCategoria() async {
    final nombreCtrl = TextEditingController();
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: nombreCtrl,
          decoration: const InputDecoration(labelText: 'Nombre de la categoría'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (resultado == true && nombreCtrl.text.trim().isNotEmpty) {
      setState(() {
        categorias.add(CategoriaConfig(nombre: nombreCtrl.text.trim(), icono: Icons.label));
      });
      await _guardarCategorias();
    }
  }

  Future<void> _eliminarCategoria(CategoriaConfig cat) async {
    setState(() {
      categorias.remove(cat);
      gastos.removeWhere((g) => g.categoria == cat.nombre);
    });
    await _guardarCategorias();
    await _guardarGastos();
  }

  /// Copia el presupuesto planeado para el próximo mes como el presupuesto
  /// del mes actual. Útil cuando el mes cambia.
  Future<void> _aplicarPresupuestoProximoMes() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aplicar presupuesto'),
        content: const Text(
            'Esto reemplazará el presupuesto del mes actual con lo que planeaste para el próximo mes. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar')),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() {
        for (final c in categorias) {
          c.estimadoMesActual = c.estimadoProximoMes;
        }
      });
      await _guardarCategorias();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Presupuesto actualizado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Finanzas'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Este mes'),
            Tab(text: 'Gráficas'),
            Tab(text: 'Próximo mes'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_tabController.index == 0) {
            return FloatingActionButton.extended(
              onPressed: _registrarGasto,
              icon: const Icon(Icons.add),
              label: const Text('Gasto'),
            );
          } else if (_tabController.index == 2) {
            return FloatingActionButton.extended(
              onPressed: _agregarCategoria,
              icon: const Icon(Icons.add),
              label: const Text('Categoría'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _EsteMesTab(
            categorias: categorias,
            gastosMesActual: gastosMesActual,
            totalEstimado: totalEstimadoMesActual,
            totalGastado: totalGastadoMesActual,
            gastadoPorCategoria: gastadoPorCategoria,
            onEditarPresupuesto: (c) => _editarPresupuesto(c, proximoMes: false),
            onEliminarCategoria: _eliminarCategoria,
            onEliminarGasto: _eliminarGasto,
          ),
          _GraficasTab(
            categorias: categorias,
            gastadoPorCategoria: gastadoPorCategoria,
            totalGastado: totalGastadoMesActual,
          ),
          _ProximoMesTab(
            categorias: categorias,
            totalEstimadoProximoMes: totalEstimadoProximoMes,
            onEditarPresupuesto: (c) => _editarPresupuesto(c, proximoMes: true),
            onAplicar: _aplicarPresupuestoProximoMes,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PESTAÑA: ESTE MES
// ---------------------------------------------------------------------------

class _EsteMesTab extends StatelessWidget {
  final List<CategoriaConfig> categorias;
  final List<Gasto> gastosMesActual;
  final double totalEstimado;
  final double totalGastado;
  final double Function(String nombre) gastadoPorCategoria;
  final void Function(CategoriaConfig) onEditarPresupuesto;
  final void Function(CategoriaConfig) onEliminarCategoria;
  final void Function(Gasto) onEliminarGasto;

  const _EsteMesTab({
    required this.categorias,
    required this.gastosMesActual,
    required this.totalEstimado,
    required this.totalGastado,
    required this.gastadoPorCategoria,
    required this.onEditarPresupuesto,
    required this.onEliminarCategoria,
    required this.onEliminarGasto,
  });

  @override
  Widget build(BuildContext context) {
    final disponible = totalEstimado - totalGastado;
    final porcentajeUsado =
        totalEstimado == 0 ? 0.0 : (totalGastado / totalEstimado).clamp(0.0, 1.5);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ResumenCard(
          totalEstimado: totalEstimado,
          totalGastado: totalGastado,
          disponible: disponible,
          porcentajeUsado: porcentajeUsado.toDouble(),
        ),
        const SizedBox(height: 20),
        const Text('Categorías', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...categorias.map((cat) {
          final gastado = gastadoPorCategoria(cat.nombre);
          return _CategoriaTile(
            categoria: cat,
            gastado: gastado,
            onTap: () => onEditarPresupuesto(cat),
            onDelete: () => onEliminarCategoria(cat),
          );
        }),
        const SizedBox(height: 24),
        const Text('Gastos recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (gastosMesActual.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no registras gastos este mes.',
                style: TextStyle(color: Colors.black54)),
          )
        else
          ...gastosMesActual.map((g) {
            final cat = categorias.firstWhere(
              (c) => c.nombre == g.categoria,
              orElse: () => CategoriaConfig(nombre: g.categoria, icono: Icons.category),
            );
            return Dismissible(
              key: ValueKey(g.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => onEliminarGasto(g),
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(cat.icono, color: Theme.of(context).colorScheme.primary),
                  title: Text(g.categoria),
                  subtitle: Text(
                    g.nota.isEmpty ? formatoFecha(g.fecha) : '${formatoFecha(g.fecha)} · ${g.nota}',
                  ),
                  trailing: Text('\$${g.monto.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PESTAÑA: GRÁFICAS
// ---------------------------------------------------------------------------

class _GraficasTab extends StatelessWidget {
  final List<CategoriaConfig> categorias;
  final double Function(String nombre) gastadoPorCategoria;
  final double totalGastado;

  const _GraficasTab({
    required this.categorias,
    required this.gastadoPorCategoria,
    required this.totalGastado,
  });

  @override
  Widget build(BuildContext context) {
    final conGasto = categorias
        .map((c) => MapEntry(c, gastadoPorCategoria(c.nombre)))
        .where((e) => e.value > 0)
        .toList();

    if (conGasto.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Registra algunos gastos este mes para ver tus gráficas aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 16),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Gasto por categoría (mes actual)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: List.generate(conGasto.length, (i) {
                final entry = conGasto[i];
                final porcentaje = totalGastado == 0 ? 0 : (entry.value / totalGastado) * 100;
                return PieChartSectionData(
                  value: entry.value,
                  color: colorPara(categorias.indexOf(entry.key)),
                  title: '${porcentaje.toStringAsFixed(0)}%',
                  radius: 80,
                  titleStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Leyenda con montos exactos por categoría.
        ...conGasto.map((entry) {
          final color = colorPara(categorias.indexOf(entry.key));
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.key.nombre)),
                Text('\$${entry.value.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }),
        const SizedBox(height: 28),
        const Text('Estimado vs. gastado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _maxYEstimadoGastado(),
              barGroups: List.generate(categorias.length, (i) {
                final cat = categorias[i];
                final gastado = gastadoPorCategoria(cat.nombre);
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: cat.estimadoMesActual, color: Colors.grey.shade400, width: 8),
                  BarChartRodData(
                      toY: gastado,
                      color: gastado > cat.estimadoMesActual && cat.estimadoMesActual > 0
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                      width: 8),
                ]);
              }),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= categorias.length) return const SizedBox.shrink();
                      final nombre = categorias[i].nombre;
                      final corto = nombre.length > 6 ? '${nombre.substring(0, 6)}…' : nombre;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(corto, style: const TextStyle(fontSize: 9)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _leyendaBarra(Colors.grey.shade400, 'Estimado'),
            const SizedBox(width: 16),
            _leyendaBarra(Theme.of(context).colorScheme.primary, 'Gastado'),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  double _maxYEstimadoGastado() {
    double maxV = 0;
    for (final c in categorias) {
      maxV = [maxV, c.estimadoMesActual, gastadoPorCategoria(c.nombre)].reduce((a, b) => a > b ? a : b);
    }
    return maxV == 0 ? 100 : maxV * 1.2;
  }

  Widget _leyendaBarra(Color color, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PESTAÑA: PRÓXIMO MES
// ---------------------------------------------------------------------------

class _ProximoMesTab extends StatelessWidget {
  final List<CategoriaConfig> categorias;
  final double totalEstimadoProximoMes;
  final void Function(CategoriaConfig) onEditarPresupuesto;
  final VoidCallback onAplicar;

  const _ProximoMesTab({
    required this.categorias,
    required this.totalEstimadoProximoMes,
    required this.onEditarPresupuesto,
    required this.onAplicar,
  });

  @override
  Widget build(BuildContext context) {
    final proximoMesNombre = nombreMes(DateTime.now().month % 12 + 1);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Planeación de $proximoMesNombre',
                    style: const TextStyle(fontSize: 16, color: Colors.black54)),
                const SizedBox(height: 8),
                Text('\$${totalEstimadoProximoMes.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Anota aquí lo que ya sabes que vas a gastar el próximo mes, como el pago de un crédito o una renta.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onAplicar,
                  icon: const Icon(Icons.sync_alt),
                  label: const Text('Usar esto como presupuesto del mes actual'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Por categoría', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...categorias.map((cat) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                onTap: () => onEditarPresupuesto(cat),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  child: Icon(cat.icono, color: Theme.of(context).colorScheme.primary),
                ),
                title: Text(cat.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(cat.estimadoProximoMes == 0
                    ? 'Sin planear todavía'
                    : 'Planeado: \$${cat.estimadoProximoMes.toStringAsFixed(2)}'),
                trailing: const Icon(Icons.chevron_right),
              ),
            )),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// WIDGETS COMPARTIDOS
// ---------------------------------------------------------------------------

class _ResumenCard extends StatelessWidget {
  final double totalEstimado;
  final double totalGastado;
  final double disponible;
  final double porcentajeUsado;

  const _ResumenCard({
    required this.totalEstimado,
    required this.totalGastado,
    required this.disponible,
    required this.porcentajeUsado,
  });

  @override
  Widget build(BuildContext context) {
    final colorBarra = porcentajeUsado > 1
        ? Colors.red
        : porcentajeUsado > 0.85
            ? Colors.orange
            : Colors.green;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resumen del mes', style: TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 8),
            Text(
              '\$${totalGastado.toStringAsFixed(2)} de \$${totalEstimado.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: porcentajeUsado > 1 ? 1 : porcentajeUsado,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: colorBarra,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  disponible >= 0
                      ? 'Disponible: \$${disponible.toStringAsFixed(2)}'
                      : 'Excedido en: \$${(-disponible).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: disponible >= 0 ? Colors.green.shade700 : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text('${(porcentajeUsado * 100).toStringAsFixed(0)}% usado'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriaTile extends StatelessWidget {
  final CategoriaConfig categoria;
  final double gastado;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CategoriaTile({
    required this.categoria,
    required this.gastado,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progreso = categoria.estimadoMesActual == 0
        ? 0.0
        : (gastado / categoria.estimadoMesActual).clamp(0.0, 1.5);
    final color = progreso > 1
        ? Colors.red
        : progreso > 0.85
            ? Colors.orange
            : Theme.of(context).colorScheme.primary;

    return Dismissible(
      key: ValueKey(categoria.hashCode),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(categoria.icono, color: color),
          ),
          title: Text(categoria.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progreso > 1 ? 1 : progreso,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text('\$${gastado.toStringAsFixed(2)} / \$${categoria.estimadoMesActual.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
