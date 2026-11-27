import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

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

/// Etiqueta legible de un mes, por ejemplo "septiembre 2026".
String etiquetaMes(DateTime f) => '${nombreMes(f.month)} ${f.year}';

/// Clave con la que se guardan los presupuestos de un mes ("2026-09").
String claveMes(DateTime f) => '${f.year}-${f.month.toString().padLeft(2, '0')}';

/// Primer día del mes siguiente (Dart ajusta solo el cambio de año).
DateTime mesSiguiente(DateTime f) => DateTime(f.year, f.month + 1);

/// Primer día del mes anterior.
DateTime mesAnterior(DateTime f) => DateTime(f.year, f.month - 1);

/// Cuántos meses hacia atrás se puede consultar el histórico.
const int mesesDeHistorico = 12;

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

  /// Presupuesto de cada mes, con clave "AAAA-MM" (ver [claveMes]).
  /// Cada mes tiene su propio monto, así que cambiar el de un mes
  /// nunca modifica los demás.
  Map<String, double> presupuestos;
  List<ArticuloItem> articulos;
  String nota; // anotación libre, útil p. ej. para distinguir a qué crédito se refiere

  CategoriaConfig({
    required this.nombre,
    required this.icono,
    Map<String, double>? presupuestos,
    List<ArticuloItem>? articulos,
    this.nota = '',
  })  : presupuestos = presupuestos ?? {},
        articulos = articulos ?? [];

  double presupuestoDe(String clave) => presupuestos[clave] ?? 0;

  void setPresupuesto(String clave, double valor) {
    if (valor > 0) {
      presupuestos[clave] = valor;
    } else {
      presupuestos.remove(clave);
    }
  }

  /// Suma de (precio x cantidad) de todos los artículos listados en esta
  /// categoría. Sirve para estimar cuánto se gastará en el mes en base a
  /// una lista de productos, por ejemplo artículos de limpieza.
  double get totalArticulos =>
      articulos.fold(0.0, (sum, a) => sum + (a.precio * a.cantidad));

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'icono': icono.codePoint,
        'presupuestos': presupuestos,
        'articulos': articulos.map((a) => a.toJson()).toList(),
        'nota': nota,
      };

  factory CategoriaConfig.fromJson(Map<String, dynamic> json) {
    final presupuestos = <String, double>{};
    final guardados = json['presupuestos'];
    if (guardados is Map) {
      guardados.forEach((k, v) => presupuestos['$k'] = (v as num).toDouble());
    } else {
      // Formato anterior (un solo "mes actual" y un solo "próximo mes"):
      // se asignan al mes en curso y al siguiente, para no perder nada.
      final ahora = DateTime.now();
      final actual = (json['estimadoMesActual'] as num?)?.toDouble() ?? 0;
      final proximo = (json['estimadoProximoMes'] as num?)?.toDouble() ?? 0;
      if (actual > 0) presupuestos[claveMes(ahora)] = actual;
      if (proximo > 0) presupuestos[claveMes(mesSiguiente(ahora))] = proximo;
    }
    return CategoriaConfig(
      nombre: json['nombre'],
      icono: IconData(json['icono'], fontFamily: 'MaterialIcons'),
      presupuestos: presupuestos,
      articulos: (json['articulos'] as List<dynamic>? ?? [])
          .map((e) => ArticuloItem.fromJson(e))
          .toList(),
      nota: json['nota'] ?? '',
    );
  }
}

/// ¿Alguna categoría guardada está todavía en el formato anterior?
bool hayCategoriasEnFormatoAnterior(List<dynamic> lista) =>
    lista.any((e) => e is Map && !e.containsKey('presupuestos'));

/// Un producto dentro de la lista de artículos de una categoría
/// (por ejemplo, "Jabón" a $35 dentro de "Artículos de limpieza").
class ArticuloItem {
  String id;
  String nombre;
  double precio;
  double cantidad;

  ArticuloItem({
    required this.id,
    required this.nombre,
    required this.precio,
    this.cantidad = 1,
  });

  double get subtotal => precio * cantidad;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'precio': precio,
        'cantidad': cantidad,
      };

  factory ArticuloItem.fromJson(Map<String, dynamic> json) => ArticuloItem(
        id: json['id'],
        nombre: json['nombre'],
        precio: (json['precio'] as num).toDouble(),
        cantidad: (json['cantidad'] as num?)?.toDouble() ?? 1,
      );
}

class Gasto {
  String id;
  String categoria; // nombre de la categoría
  double monto;
  DateTime fecha;
  String nota;
  List<ArticuloItem> detalle; // desglose opcional, ej. lista de mercado

  Gasto({
    required this.id,
    required this.categoria,
    required this.monto,
    required this.fecha,
    this.nota = '',
    List<ArticuloItem>? detalle,
  }) : detalle = detalle ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoria': categoria,
        'monto': monto,
        'fecha': fecha.toIso8601String(),
        'nota': nota,
        'detalle': detalle.map((a) => a.toJson()).toList(),
      };

  factory Gasto.fromJson(Map<String, dynamic> json) => Gasto(
        id: json['id'],
        categoria: json['categoria'],
        monto: (json['monto'] as num).toDouble(),
        fecha: DateTime.parse(json['fecha']),
        nota: json['nota'] ?? '',
        detalle: (json['detalle'] as List<dynamic>? ?? [])
            .map((e) => ArticuloItem.fromJson(e))
            .toList(),
      );
}

/// Un artículo dentro de la lista de compras planeadas para la mudanza.
class ArticuloMudanza {
  String id;
  String nombre;
  double precioEstimado;
  bool comprado;

  ArticuloMudanza({
    required this.id,
    required this.nombre,
    required this.precioEstimado,
    this.comprado = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'precioEstimado': precioEstimado,
        'comprado': comprado,
      };

  factory ArticuloMudanza.fromJson(Map<String, dynamic> json) => ArticuloMudanza(
        id: json['id'],
        nombre: json['nombre'],
        precioEstimado: (json['precioEstimado'] as num).toDouble(),
        comprado: json['comprado'] as bool? ?? false,
      );
}

/// Formatea una cantidad sin decimales innecesarios (ej. 2 en vez de 2.0).
String formatoCantidad(double c) =>
    c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toString();

/// Diálogo reutilizable para capturar un artículo (nombre, precio, cantidad).
/// Se usa tanto en el detalle de un gasto como en las listas de artículos.
Future<ArticuloItem?> mostrarDialogoArticulo(BuildContext context,
    {String tituloCampo = 'Nombre del artículo', ArticuloItem? existente}) {
  final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
  final precioCtrl =
      TextEditingController(text: existente == null ? '' : existente.precio.toStringAsFixed(2));
  final cantidadCtrl =
      TextEditingController(text: existente == null ? '1' : formatoCantidad(existente.cantidad));

  return showDialog<ArticuloItem>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existente == null ? 'Agregar artículo' : 'Editar artículo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nombreCtrl,
            autofocus: true,
            decoration: InputDecoration(labelText: tituloCampo),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: precioCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio', prefixText: '\$ '),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: cantidadCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final nombre = nombreCtrl.text.trim();
            final precio = double.tryParse(precioCtrl.text) ?? 0;
            final cantidad = double.tryParse(cantidadCtrl.text) ?? 1;
            if (nombre.isEmpty || precio <= 0) return;
            Navigator.pop(
              context,
              ArticuloItem(
                id: existente?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                nombre: nombre,
                precio: precio,
                cantidad: cantidad,
              ),
            );
          },
          child: Text(existente == null ? 'Agregar' : 'Guardar'),
        ),
      ],
    ),
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
  List<ArticuloMudanza> mudanza = [];
  bool cargando = true;
  late TabController _tabController;

  /// Mes que se está viendo (siempre día 1). Se puede mover hasta
  /// [mesesDeHistorico] meses atrás y el mismo tanto hacia adelante.
  DateTime mesSeleccionado = DateTime(DateTime.now().year, DateTime.now().month);

  DateTime get _mesActual => DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get _mesMinimo => DateTime(_mesActual.year, _mesActual.month - mesesDeHistorico);
  DateTime get _mesMaximo => DateTime(_mesActual.year, _mesActual.month + mesesDeHistorico);

  void _irAMes(DateTime m) {
    if (m.isBefore(_mesMinimo) || m.isAfter(_mesMaximo)) return;
    setState(() => mesSeleccionado = DateTime(m.year, m.month));
  }

  static const _keyCategorias = 'categorias_finanzas_v2';
  static const _keyGastos = 'gastos_finanzas_v1';
  static const _keyMudanza = 'mudanza_articulos_v1';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      final enFormatoAnterior = hayCategoriasEnFormatoAnterior(lista);
      categorias = lista.map((e) => CategoriaConfig.fromJson(e)).toList();
      // Guarda ya el formato nuevo para que la migración ocurra una sola vez.
      if (enFormatoAnterior) {
        await prefs.setString(
            _keyCategorias, jsonEncode(categorias.map((c) => c.toJson()).toList()));
      }
    } else {
      categorias = categoriasPorDefecto();
    }

    final dataGastos = prefs.getString(_keyGastos);
    if (dataGastos != null) {
      final List<dynamic> lista = jsonDecode(dataGastos);
      gastos = lista.map((e) => Gasto.fromJson(e)).toList();
    }

    final dataMudanza = prefs.getString(_keyMudanza);
    if (dataMudanza != null) {
      final List<dynamic> lista = jsonDecode(dataMudanza);
      mudanza = lista.map((e) => ArticuloMudanza.fromJson(e)).toList();
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

  Future<void> _guardarMudanza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyMudanza, jsonEncode(mudanza.map((a) => a.toJson()).toList()));
  }

  // --- Cálculos sobre el mes seleccionado ------------------------------
  // (los nombres conservan "MesActual" por compatibilidad, pero ahora se
  // refieren al mes elegido en el selector)

  List<Gasto> _gastosDelMes(DateTime m) => gastos
      .where((g) => g.fecha.year == m.year && g.fecha.month == m.month)
      .toList();

  List<Gasto> get gastosMesActual =>
      _gastosDelMes(mesSeleccionado)..sort((a, b) => b.fecha.compareTo(a.fecha));

  double gastadoPorCategoria(String nombre) => gastosMesActual
      .where((g) => g.categoria == nombre)
      .fold(0.0, (sum, g) => sum + g.monto);

  double _presupuestoTotal(DateTime m) =>
      categorias.fold(0.0, (sum, c) => sum + c.presupuestoDe(claveMes(m)));

  double get totalEstimadoMesActual => _presupuestoTotal(mesSeleccionado);

  double get totalGastadoMesActual =>
      gastosMesActual.fold(0, (sum, g) => sum + g.monto);

  double get totalEstimadoProximoMes => _presupuestoTotal(mesSiguiente(mesSeleccionado));

  /// Presupuesto y gasto de los 12 meses que terminan en el mes seleccionado.
  List<ResumenMes> get historial {
    return List.generate(12, (i) {
      final m = DateTime(mesSeleccionado.year, mesSeleccionado.month - 11 + i);
      final gastado = _gastosDelMes(m).fold(0.0, (s, g) => s + g.monto);
      return ResumenMes(m, gastado, _presupuestoTotal(m));
    });
  }

  // --- Acciones ----------------------------------------------------------

  Future<void> _registrarOEditarGasto({Gasto? existente}) async {
    if (categorias.isEmpty) return;
    String categoriaSeleccionada = existente?.categoria ?? categorias.first.nombre;
    final montoCtrl = TextEditingController(
        text: existente == null ? '' : existente.monto.toStringAsFixed(2));
    final notaCtrl = TextEditingController(text: existente?.nota ?? '');
    // Si se está viendo otro mes, el gasto nuevo cae en ese mes (hoy si es el
    // actual; si no, el mismo día del mes, ajustado a su último día).
    final hoy = DateTime.now();
    final diasDelMes = DateTime(mesSeleccionado.year, mesSeleccionado.month + 1, 0).day;
    DateTime fecha = existente?.fecha ??
        (mesSeleccionado == _mesActual
            ? hoy
            : DateTime(mesSeleccionado.year, mesSeleccionado.month,
                hoy.day > diasDelMes ? diasDelMes : hoy.day));
    List<ArticuloItem> detalleItems =
        existente == null ? [] : List<ArticuloItem>.from(existente.detalle);

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sumaDetalle = detalleItems.fold(0.0, (s, a) => s + a.subtotal);
            if (detalleItems.isNotEmpty) {
              montoCtrl.text = sumaDetalle.toStringAsFixed(2);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(existente == null ? 'Registrar gasto' : 'Editar gasto',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      autofocus: detalleItems.isEmpty,
                      readOnly: detalleItems.isNotEmpty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Monto gastado',
                        prefixText: '\$ ',
                        border: const OutlineInputBorder(),
                        helperText: detalleItems.isNotEmpty
                            ? 'Se calcula solo, según los artículos de abajo'
                            : null,
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
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Detalle de la compra (opcional)',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        TextButton.icon(
                          onPressed: () async {
                            final item = await mostrarDialogoArticulo(context);
                            if (item != null) setModalState(() => detalleItems.add(item));
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    Text(
                      'Útil para tu lista de mercado: anota cada producto que compraste ese día.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    ...detalleItems.map((it) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onTap: () async {
                            final editado = await mostrarDialogoArticulo(context, existente: it);
                            if (editado != null) {
                              setModalState(() {
                                it.nombre = editado.nombre;
                                it.precio = editado.precio;
                                it.cantidad = editado.cantidad;
                              });
                            }
                          },
                          title: Text(it.nombre),
                          subtitle: Text(
                              '\$${it.precio.toStringAsFixed(2)} x ${formatoCantidad(it.cantidad)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('\$${it.subtotal.toStringAsFixed(2)}'),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setModalState(() => detalleItems.remove(it)),
                              ),
                            ],
                          ),
                        )),
                    if (detalleItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('Total del detalle: \$${sumaDetalle.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (existente != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                gastos.removeWhere((e) => e.id == existente.id);
                                Navigator.pop(context, true);
                              },
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('Eliminar'),
                              ),
                            ),
                          ),
                        if (existente != null) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              final monto = detalleItems.isNotEmpty
                                  ? sumaDetalle
                                  : (double.tryParse(montoCtrl.text) ?? 0);
                              if (monto <= 0) return;
                              if (existente != null) {
                                existente.categoria = categoriaSeleccionada;
                                existente.monto = monto;
                                existente.fecha = fecha;
                                existente.nota = notaCtrl.text.trim();
                                existente.detalle = List<ArticuloItem>.from(detalleItems);
                              } else {
                                gastos.add(Gasto(
                                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                                  categoria: categoriaSeleccionada,
                                  monto: monto,
                                  fecha: fecha,
                                  nota: notaCtrl.text.trim(),
                                  detalle: List<ArticuloItem>.from(detalleItems),
                                ));
                              }
                              Navigator.pop(context, true);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(existente == null ? 'Guardar gasto' : 'Guardar cambios'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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

  Future<void> _editarPresupuesto(CategoriaConfig cat, {required DateTime mes}) async {
    final actual = cat.presupuestoDe(claveMes(mes));
    final ctrl = TextEditingController(
      text: actual == 0 ? '' : actual.toStringAsFixed(2),
    );
    final notaCtrl = TextEditingController(text: cat.nota);

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
                'Presupuesto de ${etiquetaMes(mes)}',
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
              const SizedBox(height: 12),
              TextField(
                controller: notaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Anotación (opcional)',
                  hintText: 'Ej. "Tarjeta Santander" o "Crédito del auto"',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final valor = double.tryParse(ctrl.text) ?? 0;
                  cat.setPresupuesto(claveMes(mes), valor);
                  cat.nota = notaCtrl.text.trim();
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

  /// Copia el presupuesto planeado para el mes siguiente al seleccionado como
  /// presupuesto del mes seleccionado. Los demás meses no se tocan.
  Future<void> _aplicarPresupuestoProximoMes() async {
    final destino = mesSeleccionado;
    final origen = mesSiguiente(mesSeleccionado);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aplicar presupuesto'),
        content: Text(
            'Esto reemplazará el presupuesto de ${etiquetaMes(destino)} con lo que planeaste para ${etiquetaMes(origen)}. ¿Continuar?'),
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
          c.setPresupuesto(claveMes(destino), c.presupuestoDe(claveMes(origen)));
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

  /// Junta categorías y gastos en un solo archivo JSON y abre el panel para
  /// compartirlo/guardarlo (Drive, correo, Archivos, WhatsApp, etc.).
  Future<void> _exportarRespaldo() async {
    try {
      final respaldo = {
        'version': 1,
        'fechaExportacion': DateTime.now().toIso8601String(),
        'categorias': categorias.map((c) => c.toJson()).toList(),
        'gastos': gastos.map((g) => g.toJson()).toList(),
        'mudanza': mudanza.map((a) => a.toJson()).toList(),
      };

      final directorio = await getTemporaryDirectory();
      final ahora = DateTime.now();
      final nombreArchivo =
          'respaldo_finanzas_${ahora.year}${ahora.month.toString().padLeft(2, '0')}${ahora.day.toString().padLeft(2, '0')}.json';
      final archivo = File('${directorio.path}/$nombreArchivo');
      await archivo.writeAsString(jsonEncode(respaldo));

      await Share.shareXFiles(
        [XFile(archivo.path)],
        text: 'Respaldo de Mis Finanzas',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar el respaldo: $e')),
        );
      }
    }
  }

  /// Deja elegir un archivo .json de respaldo y, tras confirmar, reemplaza
  /// las categorías y gastos actuales con lo que traiga ese archivo.
  Future<void> _importarRespaldo() async {
    try {
      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (resultado == null || resultado.files.single.path == null) return;

      final archivo = File(resultado.files.single.path!);
      final contenido = jsonDecode(await archivo.readAsString());

      final nuevasCategorias = (contenido['categorias'] as List<dynamic>)
          .map((e) => CategoriaConfig.fromJson(e))
          .toList();
      final nuevosGastos = (contenido['gastos'] as List<dynamic>)
          .map((e) => Gasto.fromJson(e))
          .toList();
      final nuevaMudanza = (contenido['mudanza'] as List<dynamic>? ?? [])
          .map((e) => ArticuloMudanza.fromJson(e))
          .toList();

      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importar respaldo'),
          content: Text(
              'Se encontraron ${nuevasCategorias.length} categorías, ${nuevosGastos.length} gastos '
              'y ${nuevaMudanza.length} artículos de mudanza. '
              'Esto reemplazará TODA la información que tienes actualmente en la app. ¿Continuar?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reemplazar')),
          ],
        ),
      );

      if (confirmar == true) {
        setState(() {
          categorias = nuevasCategorias;
          gastos = nuevosGastos;
          mudanza = nuevaMudanza;
        });
        await _guardarCategorias();
        await _guardarGastos();
        await _guardarMudanza();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Respaldo importado correctamente')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar el respaldo: $e')),
        );
      }
    }
  }

  /// Abre la pantalla con la lista de artículos y precios de una categoría
  /// (por ejemplo, los productos de "Artículos de limpieza").
  Future<void> _abrirListaArticulos(CategoriaConfig cat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticulosScreen(
          categoria: cat,
          mes: mesSeleccionado,
          onCambio: () async {
            await _guardarCategorias();
            setState(() {});
          },
        ),
      ),
    );
  }

  // --- Mudanza -------------------------------------------------------------

  Future<void> _agregarOEditarArticuloMudanza({ArticuloMudanza? existente}) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final precioCtrl = TextEditingController(
        text: existente == null ? '' : existente.precioEstimado.toStringAsFixed(2));

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
              Text(existente == null ? 'Nuevo artículo de mudanza' : 'Editar artículo',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Artículo (ej. cajas, cinta, camión de mudanza)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio estimado',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final nombre = nombreCtrl.text.trim();
                  final precio = double.tryParse(precioCtrl.text) ?? 0;
                  if (nombre.isEmpty || precio <= 0) return;

                  if (existente != null) {
                    existente.nombre = nombre;
                    existente.precioEstimado = precio;
                  } else {
                    mudanza.add(ArticuloMudanza(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      nombre: nombre,
                      precioEstimado: precio,
                    ));
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
      await _guardarMudanza();
      setState(() {});
    }
  }

  Future<void> _eliminarArticuloMudanza(ArticuloMudanza a) async {
    setState(() => mudanza.removeWhere((e) => e.id == a.id));
    await _guardarMudanza();
  }

  Future<void> _toggleCompradoMudanza(ArticuloMudanza a) async {
    setState(() => a.comprado = !a.comprado);
    await _guardarMudanza();
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
        actions: [
          PopupMenuButton<String>(
            onSelected: (valor) {
              if (valor == 'exportar') _exportarRespaldo();
              if (valor == 'importar') _importarRespaldo();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'exportar',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('Exportar respaldo'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'importar',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('Importar respaldo'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Este mes'),
            Tab(text: 'Gráficas'),
            Tab(text: 'Próximo mes'),
            Tab(text: 'Mudanza'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_tabController.index == 0) {
            return FloatingActionButton.extended(
              onPressed: _registrarOEditarGasto,
              icon: const Icon(Icons.add),
              label: const Text('Gasto'),
            );
          } else if (_tabController.index == 2) {
            return FloatingActionButton.extended(
              onPressed: _agregarCategoria,
              icon: const Icon(Icons.add),
              label: const Text('Categoría'),
            );
          } else if (_tabController.index == 3) {
            return FloatingActionButton.extended(
              onPressed: () => _agregarOEditarArticuloMudanza(),
              icon: const Icon(Icons.add),
              label: const Text('Artículo'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      body: Column(
        children: [
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => _tabController.index == 3
                ? const SizedBox.shrink()
                : _selectorDeMes(),
          ),
          Expanded(child: _tabs()),
        ],
      ),
    );
  }

  /// Flechas para moverse entre meses (hasta 12 atrás y 12 adelante). Tocar el
  /// nombre del mes abre una lista para saltar directo a cualquiera.
  Widget _selectorDeMes() {
    final esActual = mesSeleccionado == _mesActual;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mes anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: mesSeleccionado.isAfter(_mesMinimo)
                ? () => _irAMes(mesAnterior(mesSeleccionado))
                : null,
          ),
          Expanded(
            child: InkWell(
              onTap: _elegirMes,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(etiquetaMes(mesSeleccionado),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (!esActual)
                      const Text('Toca para elegir otro mes',
                          style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            ),
          ),
          if (!esActual)
            TextButton(onPressed: () => _irAMes(_mesActual), child: const Text('Hoy')),
          IconButton(
            tooltip: 'Mes siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: mesSeleccionado.isBefore(_mesMaximo)
                ? () => _irAMes(mesSiguiente(mesSeleccionado))
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _elegirMes() async {
    final meses = List.generate(
      mesesDeHistorico * 2 + 1,
      (i) => DateTime(_mesActual.year, _mesActual.month - mesesDeHistorico + i),
    );
    final elegido = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: meses.reversed
              .map((m) => ListTile(
                    selected: m == mesSeleccionado,
                    title: Text(etiquetaMes(m)),
                    trailing: m == _mesActual ? const Text('actual') : null,
                    onTap: () => Navigator.pop(context, m),
                  ))
              .toList(),
        ),
      ),
    );
    if (elegido != null) _irAMes(elegido);
  }

  Widget _tabs() {
    return TabBarView(
        controller: _tabController,
        children: [
          _EsteMesTab(
            mes: mesSeleccionado,
            categorias: categorias,
            gastosMesActual: gastosMesActual,
            totalEstimado: totalEstimadoMesActual,
            totalGastado: totalGastadoMesActual,
            gastadoPorCategoria: gastadoPorCategoria,
            onEditarPresupuesto: (c) => _editarPresupuesto(c, mes: mesSeleccionado),
            onEliminarCategoria: _eliminarCategoria,
            onEliminarGasto: _eliminarGasto,
            onEditarGasto: (g) => _registrarOEditarGasto(existente: g),
            onVerArticulos: _abrirListaArticulos,
          ),
          _GraficasTab(
            mes: mesSeleccionado,
            categorias: categorias,
            gastadoPorCategoria: gastadoPorCategoria,
            totalGastado: totalGastadoMesActual,
            historial: historial,
          ),
          _ProximoMesTab(
            mes: mesSiguiente(mesSeleccionado),
            categorias: categorias,
            totalEstimadoProximoMes: totalEstimadoProximoMes,
            onEditarPresupuesto: (c) =>
                _editarPresupuesto(c, mes: mesSiguiente(mesSeleccionado)),
            onAplicar: _aplicarPresupuestoProximoMes,
            onVerArticulos: _abrirListaArticulos,
          ),
          _MudanzaTab(
            articulos: mudanza,
            onEditar: (a) => _agregarOEditarArticuloMudanza(existente: a),
            onEliminar: _eliminarArticuloMudanza,
            onToggle: _toggleCompradoMudanza,
          ),
        ],
    );
  }
}

// ---------------------------------------------------------------------------
// PESTAÑA: ESTE MES
// ---------------------------------------------------------------------------

class _EsteMesTab extends StatelessWidget {
  final DateTime mes;
  final List<CategoriaConfig> categorias;
  final List<Gasto> gastosMesActual;
  final double totalEstimado;
  final double totalGastado;
  final double Function(String nombre) gastadoPorCategoria;
  final void Function(CategoriaConfig) onEditarPresupuesto;
  final void Function(CategoriaConfig) onEliminarCategoria;
  final void Function(Gasto) onEliminarGasto;
  final void Function(Gasto) onEditarGasto;
  final void Function(CategoriaConfig) onVerArticulos;

  const _EsteMesTab({
    required this.mes,
    required this.categorias,
    required this.gastosMesActual,
    required this.totalEstimado,
    required this.totalGastado,
    required this.gastadoPorCategoria,
    required this.onEditarPresupuesto,
    required this.onEliminarCategoria,
    required this.onEliminarGasto,
    required this.onEditarGasto,
    required this.onVerArticulos,
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
            presupuesto: cat.presupuestoDe(claveMes(mes)),
            onTap: () => onEditarPresupuesto(cat),
            onDelete: () => onEliminarCategoria(cat),
            onVerArticulos: () => onVerArticulos(cat),
          );
        }),
        const SizedBox(height: 24),
        const Text('Gastos recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (gastosMesActual.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No hay gastos registrados en ${etiquetaMes(mes)}.',
                style: const TextStyle(color: Colors.black54)),
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
                  onTap: () => onEditarGasto(g),
                  leading: Icon(cat.icono, color: Theme.of(context).colorScheme.primary),
                  title: Text(g.categoria),
                  subtitle: Text(
                    [
                      formatoFecha(g.fecha),
                      if (g.nota.isNotEmpty) g.nota,
                      if (g.detalle.isNotEmpty) '${g.detalle.length} artículos',
                    ].join(' · '),
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

/// Totales de un mes, para la gráfica del último año.
class ResumenMes {
  final DateTime mes;
  final double gastado;
  final double presupuesto;
  const ResumenMes(this.mes, this.gastado, this.presupuesto);
}

class _GraficasTab extends StatelessWidget {
  final DateTime mes;
  final List<CategoriaConfig> categorias;
  final double Function(String nombre) gastadoPorCategoria;
  final double totalGastado;
  final List<ResumenMes> historial; // 12 meses terminando en el mes visto

  const _GraficasTab({
    required this.mes,
    required this.categorias,
    required this.gastadoPorCategoria,
    required this.totalGastado,
    required this.historial,
  });

  @override
  Widget build(BuildContext context) {
    final conGasto = categorias
        .map((c) => MapEntry(c, gastadoPorCategoria(c.nombre)))
        .where((e) => e.value > 0)
        .toList();

    final historialWidget = _historialAnual(context);

    if (conGasto.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No hay gastos en ${etiquetaMes(mes)} para graficar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 16),
            ),
          ),
          ...historialWidget,
          const SizedBox(height: 40),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Gasto por categoría (${etiquetaMes(mes)})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  BarChartRodData(
                      toY: cat.presupuestoDe(claveMes(mes)), color: Colors.grey.shade400, width: 8),
                  BarChartRodData(
                      toY: gastado,
                      color: gastado > cat.presupuestoDe(claveMes(mes)) &&
                              cat.presupuestoDe(claveMes(mes)) > 0
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
        const SizedBox(height: 28),
        ...historialWidget,
        const SizedBox(height: 40),
      ],
    );
  }

  /// Gráfica de los últimos 12 meses: presupuesto vs. gastado de cada uno.
  List<Widget> _historialAnual(BuildContext context) {
    double maxV = 0;
    for (final r in historial) {
      if (r.gastado > maxV) maxV = r.gastado;
      if (r.presupuesto > maxV) maxV = r.presupuesto;
    }
    final primario = Theme.of(context).colorScheme.primary;
    return [
      const Text('Últimos 12 meses',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Termina en ${etiquetaMes(mes)}',
          style: const TextStyle(color: Colors.black54, fontSize: 12)),
      const SizedBox(height: 16),
      SizedBox(
        height: 240,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxV == 0 ? 100 : maxV * 1.2,
            barGroups: List.generate(historial.length, (i) {
              final r = historial[i];
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: r.presupuesto, color: Colors.grey.shade400, width: 5),
                BarChartRodData(
                    toY: r.gastado,
                    color: r.presupuesto > 0 && r.gastado > r.presupuesto ? Colors.red : primario,
                    width: 5),
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
                    if (i < 0 || i >= historial.length) return const SizedBox.shrink();
                    final nombre = nombreMes(historial[i].mes.month);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(nombre.substring(0, 3), style: const TextStyle(fontSize: 9)),
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
          _leyendaBarra(Colors.grey.shade400, 'Presupuesto'),
          const SizedBox(width: 16),
          _leyendaBarra(primario, 'Gastado'),
        ],
      ),
    ];
  }

  double _maxYEstimadoGastado() {
    double maxV = 0;
    for (final c in categorias) {
      maxV = [maxV, c.presupuestoDe(claveMes(mes)), gastadoPorCategoria(c.nombre)]
          .reduce((a, b) => a > b ? a : b);
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
  /// Mes que se está planeando (el siguiente al que se ve en "Este mes").
  final DateTime mes;
  final List<CategoriaConfig> categorias;
  final double totalEstimadoProximoMes;
  final void Function(CategoriaConfig) onEditarPresupuesto;
  final VoidCallback onAplicar;
  final void Function(CategoriaConfig) onVerArticulos;

  const _ProximoMesTab({
    required this.mes,
    required this.categorias,
    required this.totalEstimadoProximoMes,
    required this.onEditarPresupuesto,
    required this.onAplicar,
    required this.onVerArticulos,
  });

  @override
  Widget build(BuildContext context) {
    final proximoMesNombre = etiquetaMes(mes);

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
                  label: Text('Usar esto como presupuesto de ${etiquetaMes(mesAnterior(mes))}'),
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cat.nota.isNotEmpty)
                      Text(cat.nota,
                          style: const TextStyle(
                              fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54)),
                    Text(cat.presupuestoDe(claveMes(mes)) == 0
                        ? 'Sin planear todavía'
                        : 'Planeado: \$${cat.presupuestoDe(claveMes(mes)).toStringAsFixed(2)}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Lista de artículos',
                      icon: const Icon(Icons.list_alt),
                      onPressed: () => onVerArticulos(cat),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            )),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PESTAÑA: MUDANZA
// ---------------------------------------------------------------------------

/// Lista independiente de artículos a comprar para la mudanza, con precio
/// estimado, para ir anticipando cuánto va a costar en total.
class _MudanzaTab extends StatelessWidget {
  final List<ArticuloMudanza> articulos;
  final void Function(ArticuloMudanza) onEditar;
  final void Function(ArticuloMudanza) onEliminar;
  final void Function(ArticuloMudanza) onToggle;

  const _MudanzaTab({
    required this.articulos,
    required this.onEditar,
    required this.onEliminar,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final totalEstimado = articulos.fold(0.0, (s, a) => s + a.precioEstimado);
    final totalComprado =
        articulos.where((a) => a.comprado).fold(0.0, (s, a) => s + a.precioEstimado);
    final totalPendiente = totalEstimado - totalComprado;

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
                const Text('Presupuesto de la mudanza', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                Text('\$${totalEstimado.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Anota aquí todo lo que necesitas comprar para la mudanza (cajas, servicio de '
                  'camión, empaque, etc.) para ir anticipando cuánto vas a gastar en total.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ya comprado', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          Text('\$${totalComprado.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Falta comprar', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          Text('\$${totalPendiente.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Artículos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (articulos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Todavía no agregas artículos para la mudanza. Usa el botón "+" para empezar tu lista.',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else
          ...articulos.map((a) => Dismissible(
                key: ValueKey(a.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration:
                      BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => onEliminar(a),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => onEditar(a),
                    leading: Checkbox(
                      value: a.comprado,
                      onChanged: (_) => onToggle(a),
                    ),
                    title: Text(
                      a.nombre,
                      style: TextStyle(
                        decoration: a.comprado ? TextDecoration.lineThrough : null,
                        color: a.comprado ? Colors.black45 : null,
                      ),
                    ),
                    subtitle: Text(a.comprado ? 'Comprado' : 'Pendiente'),
                    trailing: Text('\$${a.precioEstimado.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
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
  final double presupuesto; // presupuesto del mes que se está viendo
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onVerArticulos;

  const _CategoriaTile({
    required this.categoria,
    required this.gastado,
    required this.presupuesto,
    required this.onTap,
    required this.onDelete,
    required this.onVerArticulos,
  });

  @override
  Widget build(BuildContext context) {
    final progreso = presupuesto == 0 ? 0.0 : (gastado / presupuesto).clamp(0.0, 1.5);
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
                if (categoria.nota.isNotEmpty) ...[
                  Text(
                    categoria.nota,
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                ],
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
                Text('\$${gastado.toStringAsFixed(2)} / \$${presupuesto.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (categoria.articulos.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${categoria.articulos.length} artículos listados · \$${categoria.totalArticulos.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Lista de artículos',
                icon: const Icon(Icons.list_alt),
                onPressed: onVerArticulos,
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PANTALLA: LISTA DE ARTÍCULOS DE UNA CATEGORÍA
// ---------------------------------------------------------------------------

/// Pantalla donde el usuario lista productos con su precio dentro de una
/// categoría (por ejemplo, los artículos que compra normalmente de limpieza
/// o de cuidado personal), para calcular cuánto sumaría gastar en ellos.
class ArticulosScreen extends StatefulWidget {
  final CategoriaConfig categoria;

  /// Mes que se está viendo en la app; los botones de "usar como presupuesto"
  /// aplican a este mes y al siguiente.
  final DateTime mes;
  final VoidCallback onCambio;

  const ArticulosScreen({
    super.key,
    required this.categoria,
    required this.mes,
    required this.onCambio,
  });

  @override
  State<ArticulosScreen> createState() => _ArticulosScreenState();
}

class _ArticulosScreenState extends State<ArticulosScreen> {
  Future<void> _agregarOEditarArticulo({ArticuloItem? existente}) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final precioCtrl =
        TextEditingController(text: existente == null ? '' : existente.precio.toStringAsFixed(2));
    final cantidadCtrl =
        TextEditingController(text: existente == null ? '1' : _formatoCantidad(existente.cantidad));

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
              Text(existente == null ? 'Nuevo artículo' : 'Editar artículo',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre del artículo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: precioCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Precio unitario',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: cantidadCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final nombre = nombreCtrl.text.trim();
                  final precio = double.tryParse(precioCtrl.text) ?? 0;
                  final cantidad = double.tryParse(cantidadCtrl.text) ?? 1;
                  if (nombre.isEmpty || precio <= 0) return;

                  if (existente != null) {
                    existente.nombre = nombre;
                    existente.precio = precio;
                    existente.cantidad = cantidad;
                  } else {
                    widget.categoria.articulos.add(ArticuloItem(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      nombre: nombre,
                      precio: precio,
                      cantidad: cantidad,
                    ));
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
      widget.onCambio();
      setState(() {});
    }
  }

  void _eliminarArticulo(ArticuloItem a) {
    setState(() => widget.categoria.articulos.remove(a));
    widget.onCambio();
  }

  Future<void> _usarComoPresupuesto({required DateTime mes}) async {
    final total = widget.categoria.totalArticulos;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usar como presupuesto'),
        content: Text(
          'Se usará \$${total.toStringAsFixed(2)} como presupuesto de ${etiquetaMes(mes)} para "${widget.categoria.nombre}". Los demás meses no cambian.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aplicar')),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() {
        widget.categoria.setPresupuesto(claveMes(mes), total);
      });
      widget.onCambio();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Presupuesto actualizado')),
        );
      }
    }
  }

  String _formatoCantidad(double c) => c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toString();

  @override
  Widget build(BuildContext context) {
    final articulos = widget.categoria.articulos;
    final total = widget.categoria.totalArticulos;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoria.nombre),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _agregarOEditarArticulo(),
        icon: const Icon(Icons.add),
        label: const Text('Artículo'),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total de la lista', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text('\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: articulos.isEmpty ? null : () => _usarComoPresupuesto(mes: widget.mes),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('Usar en ${nombreMes(widget.mes.month)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: articulos.isEmpty
                            ? null
                            : () => _usarComoPresupuesto(mes: mesSiguiente(widget.mes)),
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text('Usar en ${nombreMes(mesSiguiente(widget.mes).month)}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: articulos.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Todavía no agregas artículos. Usa el botón "+" para empezar tu lista.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    itemCount: articulos.length,
                    itemBuilder: (context, i) {
                      final a = articulos[i];
                      return Dismissible(
                        key: ValueKey(a.id),
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
                        onDismissed: (_) => _eliminarArticulo(a),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => _agregarOEditarArticulo(existente: a),
                            title: Text(a.nombre),
                            subtitle: Text(
                              '\$${a.precio.toStringAsFixed(2)} x ${_formatoCantidad(a.cantidad)}',
                            ),
                            trailing: Text('\$${a.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
