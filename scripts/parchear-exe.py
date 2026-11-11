"""Actualiza dist/Optimizador.exe sin compilar: le cambia el Optimizador.bat de adentro y la versión.

Para cuando no hay Windows a mano (Claude trabajando en la nube): toma un Optimizador.exe ya compilado
por build.ps1, le mete el Optimizador.bat nuevo y le pone la versión del .bat (en Propiedades > Detalles
y en la versión del ensamblado). El ícono, el manifiesto y el lanzador quedan los del .exe original.

    python3 scripts/parchear-exe.py <exe base> <Optimizador.bat> <exe de salida>

El .bat nuevo va al final de la sección .reloc y el encabezado CLI apunta ahí. Si el .exe base ya fue
parcheado, reemplaza ese agregado en vez de sumar otro.
"""
import re, struct, sys
import pefile

def alinear(n, a): return (n + a - 1) // a * a

def main(base, bat_path, salida):
    datos = bytearray(open(base, 'rb').read())
    bat = open(bat_path, 'rb').read()
    ver = re.search(rb"^\$Version = '(\d+)\.(\d+)'", bat, re.M)
    if not ver: sys.exit('no encontré $Version en el .bat')
    may, men = int(ver.group(1)), int(ver.group(2))

    pe = pefile.PE(data=bytes(datos))
    reloc = pe.sections[-1]
    if not reloc.Name.startswith(b'.reloc'): sys.exit('la última sección no es .reloc')
    salign, falign = pe.OPTIONAL_HEADER.SectionAlignment, pe.OPTIONAL_HEADER.FileAlignment
    dd_reloc = pe.OPTIONAL_HEADER.DATA_DIRECTORY[5]
    cli_dd = pe.OPTIONAL_HEADER.DATA_DIRECTORY[14]
    cli_off = pe.get_offset_from_rva(cli_dd.VirtualAddress)
    res_rva, res_size = struct.unpack_from('<II', datos, cli_off + 24)

    # dónde arranca lo agregado: justo después de las reubicaciones (o donde estaba el agregado anterior)
    inicio_rva = alinear(dd_reloc.VirtualAddress + dd_reloc.Size, 16)
    if reloc.VirtualAddress <= res_rva < reloc.VirtualAddress + reloc.Misc_VirtualSize:
        inicio_rva = res_rva   # ya parcheado: se pisa
    inicio_off = reloc.PointerToRawData + (inicio_rva - reloc.VirtualAddress)

    # recursos administrados: [largo int32][bytes] por recurso; el .exe tiene uno solo (offset 0)
    blob = struct.pack('<I', len(bat)) + bat
    nuevo_vsize = (inicio_rva - reloc.VirtualAddress) + len(blob)
    nuevo_raw = alinear(nuevo_vsize, falign)
    del datos[reloc.PointerToRawData:]
    # se rearma la sección: lo original hasta el agregado + el blob + relleno
    orig = pe.__data__[reloc.PointerToRawData:inicio_off]
    datos += orig + b'\0' * (inicio_off - reloc.PointerToRawData - len(orig)) + blob
    datos += b'\0' * (reloc.PointerToRawData + nuevo_raw - len(datos))

    # encabezado de la sección .reloc
    sh = reloc.get_file_offset()
    struct.pack_into('<I', datos, sh + 8, nuevo_vsize)    # VirtualSize
    struct.pack_into('<I', datos, sh + 16, nuevo_raw)     # SizeOfRawData
    # tamaño de la imagen
    oh = pe.OPTIONAL_HEADER.get_file_offset()
    struct.pack_into('<I', datos, oh + 56, alinear(reloc.VirtualAddress + nuevo_vsize, salign))   # SizeOfImage
    init = pe.OPTIONAL_HEADER.SizeOfInitializedData - reloc.SizeOfRawData + nuevo_raw
    struct.pack_into('<I', datos, oh + 8, init)
    struct.pack_into('<I', datos, oh + 64, 0)   # CheckSum (no se valida en un .exe)
    # encabezado CLI: recursos
    struct.pack_into('<II', datos, cli_off + 24, inicio_rva, len(blob))

    # versión: VS_FIXEDFILEINFO, textos de VERSIONINFO, tabla Assembly y AssemblyFileVersion
    i = datos.find(b'\xbd\x04\xef\xfe')
    vieja = struct.unpack_from('<I', datos, i + 8)[0]
    vmay, vmen = vieja >> 16, vieja & 0xFFFF
    for desp in (8, 16):
        struct.pack_into('<II', datos, i + desp, (may << 16) | men, 0)
    viejo_txt, nuevo_txt = f'{vmay}.{vmen}.0.0', f'{may}.{men}.0.0'
    if len(viejo_txt) != len(nuevo_txt):
        sys.exit(f'la versión cambia de largo ({viejo_txt} -> {nuevo_txt}): compilá una vez en Windows con build.ps1')
    datos = bytearray(datos.replace(viejo_txt.encode('utf-16le'), nuevo_txt.encode('utf-16le')))
    datos = bytearray(datos.replace(viejo_txt.encode(), nuevo_txt.encode()))
    # tabla Assembly: MajorVersion, MinorVersion (uint16) justo después de HashAlgId (uint32 = 0x8004)
    patron = struct.pack('<IHH', 0x8004, vmay, vmen)
    j = datos.find(patron)
    if j < 0: sys.exit('no encontré la versión del ensamblado')
    struct.pack_into('<HH', datos, j + 4, may, men)

    open(salida, 'wb').write(datos)
    print(f'{salida}: v{may}.{men} ({len(datos)} bytes)')

if __name__ == '__main__':
    main(*sys.argv[1:4])
