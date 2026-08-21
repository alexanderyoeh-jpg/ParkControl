const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const raiz = path.resolve(__dirname, '..', '..');

function leer(relativa) {
  return fs.readFileSync(path.join(raiz, relativa), 'utf8');
}

function existe(relativa) {
  return fs.existsSync(path.join(raiz, relativa));
}

function png(relativa) {
  const contenido = fs.readFileSync(path.join(raiz, relativa));
  const firma = '89504e470d0a1a0a';

  assert.equal(
    contenido.subarray(0, 8).toString('hex'),
    firma,
    `No es un PNG válido: ${relativa}`
  );
  assert.equal(contenido.toString('ascii', 12, 16), 'IHDR');

  return {
    ancho: contenido.readUInt32BE(16),
    alto: contenido.readUInt32BE(20),
    tipoColor: contenido[25]
  };
}

function comprobarPng(relativa, ancho, alto, { sinAlpha = false } = {}) {
  assert.ok(existe(relativa), `Falta el recurso ${relativa}`);
  const metadatos = png(relativa);
  assert.equal(metadatos.ancho, ancho, `Ancho inesperado: ${relativa}`);
  assert.equal(metadatos.alto, alto, `Alto inesperado: ${relativa}`);

  if (sinAlpha) {
    // RGB (2) o escala de grises (0) no incluyen canal alfa. App Store no
    // acepta un ícono de aplicación que tenga canal alfa, incluso opaco.
    assert.ok(
      [0, 2].includes(metadatos.tipoColor),
      `El ícono iOS no puede tener canal alfa: ${relativa}`
    );
  }
}

function ejecutar() {
  const manifestAndroid = leer('android/app/src/main/AndroidManifest.xml');
  const manifestAndroidDebug = leer('android/app/src/debug/AndroidManifest.xml');
  const gradleAndroid = leer('android/app/build.gradle.kts');

  assert.match(manifestAndroid, /android\.permission\.INTERNET/);
  assert.match(manifestAndroid, /android:label="ParkControl"/);
  assert.match(manifestAndroid, /@mipmap\/ic_launcher_parkcontrol/);
  assert.doesNotMatch(manifestAndroid, /usesCleartextTraffic="true"/);
  assert.match(manifestAndroid, /android\.intent\.action\.VIEW/);
  assert.match(manifestAndroid, /android:scheme="https"/);
  assert.match(manifestAndroidDebug, /usesCleartextTraffic="true"/);
  assert.match(gradleAndroid, /applicationId = "cl\.parkcontrol\.app"/);
  assert.match(gradleAndroid, /Falta una firma de publicación válida/);

  for (const [densidad, lado] of Object.entries({
    mdpi: 48,
    hdpi: 72,
    xhdpi: 96,
    xxhdpi: 144,
    xxxhdpi: 192
  })) {
    comprobarPng(
      `android/app/src/main/res/mipmap-${densidad}/ic_launcher_parkcontrol.png`,
      lado,
      lado
    );
  }

  const infoPlist = leer('ios/Runner/Info.plist');
  const proyectoIos = leer('ios/Runner.xcodeproj/project.pbxproj');
  assert.match(infoPlist, /<string>ParkControl<\/string>/);
  assert.match(
    infoPlist,
    /<key>ITSAppUsesNonExemptEncryption<\/key>\s*<false\/>/,
    'iOS debe declarar que no usa criptografía propia no exenta',
  );
  assert.match(proyectoIos, /PRODUCT_BUNDLE_IDENTIFIER = cl\.parkcontrol\.app/);
  assert.match(proyectoIos, /ASSETCATALOG_COMPILER_APPICON_NAME = ParkControlStoreIcon/);
  assert.ok(existe('ios/Runner/PrivacyInfo.xcprivacy'));

  const directorioIconoIos = 'ios/Runner/Assets.xcassets/ParkControlStoreIcon.appiconset';
  const contenidosIos = JSON.parse(leer(`${directorioIconoIos}/Contents.json`));
  assert.ok(Array.isArray(contenidosIos.images));
  assert.ok(contenidosIos.images.length >= 15);
  for (const imagen of contenidosIos.images) {
    assert.ok(imagen.filename, 'Cada slot del ícono iOS debe tener archivo');
    const escala = Number(String(imagen.scale).replace('x', ''));
    const lado = Math.round(Number(imagen.size.split('x')[0]) * escala);
    comprobarPng(`${directorioIconoIos}/${imagen.filename}`, lado, lado, {
      sinAlpha: true
    });
  }

  const manifestWeb = JSON.parse(leer('web/manifest.json'));
  assert.equal(manifestWeb.short_name, 'ParkControl');
  assert.equal(manifestWeb.display, 'standalone');
  assert.equal(manifestWeb.theme_color, '#0F2B52');
  for (const icono of manifestWeb.icons) {
    const [ancho, alto] = icono.sizes.split('x').map(Number);
    comprobarPng(`web/${icono.src}`, ancho, alto);
  }
  const indexWeb = leer('web/index.html');
  assert.match(indexWeb, /<html lang="es">/);
  assert.match(indexWeb, /<title>ParkControl<\/title>/);
  assert.match(indexWeb, /manifest\.json/);

  console.log('Metadatos de publicación Android, iOS y web verificados.');
}

ejecutar();
