import 'dart:convert';
import 'package:flutter/material.dart';
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
// MODELO
// ---------------------------------------------------------------------------

class Categoria {
  String nombre;
  IconData icono;
  double estimado; // lo que planeo gastar
  double gastado; // lo que realmente he gastado

  Categoria({
    required this.nombre,
    required this.icono,
    this.estimado = 0,
    this.gastado = 0,
  });

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'icono': icono.codePoint,
        'estimado': estimado,
        'gastado': gastado,
      };

  factory Categoria.fromJson(Map<String, dynamic> json) => Categoria(
        nombre: json['nombre'],
        icono: IconData(json['icono'], fontFamily: 'MaterialIcons'),
        estimado: (json['estimado'] as num).toDouble(),
        gastado: (json['gastado'] as num).toDouble(),
      );
}

// Categorías por defecto sugeridas
List<Categoria> categoriasPorDefecto() => [
      Categoria(nombre: 'Comida', icono: Icons.restaurant),
      Categoria(nombre: 'Transporte', icono: Icons.directions_bus),
      Categoria(nombre: 'Entretenimiento', icono: Icons.movie),
      Categoria(nombre: 'Artículos de limpieza', icono: Icons.cleaning_services),
      Categoria(nombre: 'Cuidado personal', icono: Icons.spa),
      Categoria(nombre: 'Ahorro', icono: Icons.savings),
      Categoria(nombre: 'Pago de créditos', icono: Icons.credit_card),
      Categoria(nombre: 'Servicios (luz, agua, internet)', icono: Icons.bolt),
      Categoria(nombre: 'Otros', icono: Icons.category),
    ];

// ---------------------------------------------------------------------------
// PANTALLA PRINCIPAL
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Categoria> categorias = [];
  bool cargando = true;

  static const _prefsKey = 'categorias_finanzas';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_prefsKey);
    if (data != null) {
      final List<dynamic> lista = jsonDecode(data);
      categorias = lista.map((e) => Categoria.fromJson(e)).toList();
    } else {
      categorias = categoriasPorDefecto();
    }
    setState(() => cargando = false);
  }

  Future<void> _guardarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(categorias.map((c) => c.toJson()).toList());
    await prefs.setString(_prefsKey, data);
  }

  double get totalEstimado =>
      categorias.fold(0, (sum, c) => sum + c.estimado);

  double get totalGastado => categorias.fold(0, (sum, c) => sum + c.gastado);

  double get disponible => totalEstimado - totalGastado;

  void _editarCategoria(Categoria cat) async {
    final estimadoCtrl =
        TextEditingController(text: cat.estimado == 0 ? '' : cat.estimado.toStringAsFixed(2));
    final gastadoCtrl =
        TextEditingController(text: cat.gastado == 0 ? '' : cat.gastado.toStringAsFixed(2));

    final resultado = await showModalBottomSheet<bool>(
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
                  Text(cat.nombre,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: estimadoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Presupuesto estimado (mensual)',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gastadoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Gastado hasta ahora',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  cat.estimado = double.tryParse(estimadoCtrl.text) ?? 0;
                  cat.gastado = double.tryParse(gastadoCtrl.text) ?? 0;
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

    if (resultado == true) {
      await _guardarDatos();
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
        categorias.add(Categoria(nombre: nombreCtrl.text.trim(), icono: Icons.label));
      });
      await _guardarDatos();
    }
  }

  void _eliminarCategoria(Categoria cat) async {
    setState(() => categorias.remove(cat));
    await _guardarDatos();
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final porcentajeUsado =
        totalEstimado == 0 ? 0.0 : (totalGastado / totalEstimado).clamp(0.0, 1.5);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Finanzas'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarCategoria,
        icon: const Icon(Icons.add),
        label: const Text('Categoría'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ResumenCard(
            totalEstimado: totalEstimado,
            totalGastado: totalGastado,
            disponible: disponible,
            porcentajeUsado: porcentajeUsado.toDouble(),
          ),
          const SizedBox(height: 20),
          const Text(
            'Categorías',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...categorias.map((cat) => _CategoriaTile(
                categoria: cat,
                onTap: () => _editarCategoria(cat),
                onDelete: () => _eliminarCategoria(cat),
              )),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WIDGETS AUXILIARES
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
            const Text('Resumen del mes',
                style: TextStyle(fontSize: 16, color: Colors.black54)),
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
  final Categoria categoria;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CategoriaTile({
    required this.categoria,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progreso = categoria.estimado == 0
        ? 0.0
        : (categoria.gastado / categoria.estimado).clamp(0.0, 1.5);
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
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(14),
        ),
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
          title: Text(categoria.nombre,
              style: const TextStyle(fontWeight: FontWeight.w600)),
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
                Text(
                  '\$${categoria.gastado.toStringAsFixed(2)} / \$${categoria.estimado.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
