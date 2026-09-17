# Mis Finanzas

App sencilla en Flutter para estimar y controlar tus gastos mensuales por categoría.

## Qué hace

- Trae categorías predefinidas: Comida, Transporte, Entretenimiento, Artículos de limpieza,
  Cuidado personal, Ahorro, Pago de créditos, Servicios y Otros.
- Para cada categoría puedes capturar:
  - **Presupuesto estimado**: cuánto planeas gastar ese mes.
  - **Gastado hasta ahora**: cuánto llevas gastado realmente.
- Muestra un resumen en la parte superior con el total estimado, el total gastado,
  el porcentaje usado y si te queda disponible o ya te excediste.
- Puedes agregar categorías propias o eliminar las que no uses (deslizando hacia la izquierda).
- Los datos se guardan en el dispositivo (con `shared_preferences`), así que persisten
  aunque cierres la app.

## Cómo correrla

1. Instala Flutter (https://docs.flutter.dev/get-started/install) si no lo tienes.
2. Descomprime/copia esta carpeta `finanzas_app`.
3. Desde una terminal, dentro de la carpeta del proyecto:
   ```
   flutter pub get
   flutter run
   ```
   Puedes correrla en un emulador Android/iOS, en Chrome (`flutter run -d chrome`),
   o en tu propio celular conectado por USB.

## Estructura

```
finanzas_app/
├── pubspec.yaml       # dependencias del proyecto
└── lib/
    └── main.dart      # toda la lógica y las pantallas de la app
```

## Ideas para extender

- Agregar un historial por día/semana en vez de solo un total mensual.
- Graficar el gasto por categoría con un pie chart (paquete `fl_chart`).
- Sincronizar los datos en la nube (Firebase) para verlos desde varios dispositivos.
- Agregar notificaciones cuando una categoría se acerque a su límite.
