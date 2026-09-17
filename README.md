# Mis Finanzas

App sencilla en Flutter para estimar y controlar tus gastos mensuales por categoría.

## Qué hace

La app tiene tres pestañas:

- **Este mes**: resumen del presupuesto vs. lo gastado, progreso por categoría, y un
  botón "+" para **registrar un gasto del día** (eliges categoría, monto, fecha y una
  nota opcional). Los gastos recientes se listan abajo y puedes borrarlos deslizando.
- **Gráficas**: una gráfica de pastel con el gasto por categoría del mes actual, y una
  gráfica de barras comparando lo estimado vs. lo realmente gastado por categoría.
- **Próximo mes**: aquí planeas con anticipación lo que sabes que vas a gastar el
  siguiente mes (por ejemplo, un pago de crédito, una renta, etc.), categoría por
  categoría. Cuando llegue ese mes, puedes usar el botón "Usar esto como presupuesto
  del mes actual" para aplicarlo de un clic.

Otros detalles:
- Puedes agregar tus propias categorías o eliminar las que no uses (deslizando hacia
  la izquierda). Al borrar una categoría también se borran sus gastos registrados.
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
├── pubspec.yaml       # dependencias del proyecto (incluye fl_chart para las gráficas)
└── lib/
    └── main.dart      # toda la lógica y las pantallas de la app
```

## Ideas para extender

- Graficar la evolución del gasto semana a semana dentro del mes.
- Sincronizar los datos en la nube (Firebase) para verlos desde varios dispositivos.
- Agregar notificaciones cuando una categoría se acerque a su límite.
- Permitir gastos recurrentes automáticos (por ejemplo, que el pago de un crédito se
  registre solo cada mes).
