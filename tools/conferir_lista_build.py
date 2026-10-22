"""Confere a lista da build (tools/gerar_apk/arquivos_build.txt) antes de
publicar uma versao nova do Swish Arena:

    python3 tools/conferir_lista_build.py

O GERAR_APK_AGORA.bat trata como SOBRA de versao antiga (e tira do projeto)
todo script, cena, shader ou arquivo das pastas do jogo que NAO esteja na
lista. Um arquivo novo esquecido nela some do APK - foi assim que a
apresentacao sumiu e o jogo abriu sem a cena inicial. Este conferidor:
  1. segue, em cadeia, tudo o que o jogo cita com "res://" (a partir do
     project.godot) e avisa o que falta na lista;
  2. avisa arquivo da lista que nao existe;
  3. avisa arquivo das pastas do jogo que nao esta na lista (o .bat o
     tiraria do projeto).
Sai com erro (1) se achar qualquer problema.
"""
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LISTA = os.path.join(RAIZ, "tools", "gerar_apk", "arquivos_build.txt")
TEXTO = (".gd", ".tscn", ".tres", ".godot", ".cfg", ".shader", ".gdshader")
DO_PC = (".git", ".import", "build", "android/build", "APK-Pronto", "sobras_de_versoes_antigas")


def main():
    lista = set()
    with open(LISTA, encoding="utf-8") as f:
        for linha in f:
            if linha.strip():
                lista.add(linha.strip().replace("\\", "/"))
    problemas = []
    # 1. o que o jogo usa (em cadeia)
    usados, lidos, fila = set(), set(), ["project.godot"]
    while fila:
        rel = fila.pop()
        if rel in lidos or not rel.endswith(TEXTO):
            continue
        lidos.add(rel)
        caminho = os.path.join(RAIZ, rel)
        if not os.path.exists(caminho):
            continue
        with open(caminho, encoding="utf-8", errors="replace") as f:
            for m in re.finditer(r'res://([^"\' )\r\n]+)', f.read()):
                usado = m.group(1)
                # (texto com %s e pasta inteira: não são arquivos)
                if "%" in usado or usado.endswith("/") or os.path.isdir(os.path.join(RAIZ, usado)):
                    continue
                usados.add(usado)
                fila.append(usado)
    for u in sorted(usados):
        if u not in lista:
            problemas.append("o jogo usa e FALTA NA LISTA: " + u)
        elif not os.path.exists(os.path.join(RAIZ, u)):
            problemas.append("o jogo usa e NAO EXISTE: " + u)
        imp = u + ".import"
        if os.path.exists(os.path.join(RAIZ, imp)) and imp not in lista:
            problemas.append("FALTA NA LISTA: " + imp)
    # 2. da lista e nao existe
    for rel in sorted(lista):
        if not os.path.exists(os.path.join(RAIZ, rel)):
            problemas.append("esta na lista e NAO EXISTE: " + rel)
    # 3. nas pastas do jogo e fora da lista (o .bat tiraria do projeto)
    pastas = {rel.split("/")[0] for rel in lista if "/" in rel}
    for pasta in sorted(pastas):
        for raiz, dirs, arquivos in os.walk(os.path.join(RAIZ, pasta)):
            dirs[:] = [d for d in dirs if not os.path.relpath(os.path.join(raiz, d), RAIZ).replace("\\", "/").startswith(DO_PC)]
            for a in arquivos:
                rel = os.path.relpath(os.path.join(raiz, a), RAIZ).replace("\\", "/")
                if rel.startswith(DO_PC) or a == ".gdignore" or rel in lista:
                    continue
                if rel.startswith("tools/") and "__pycache__" in rel:
                    continue
                problemas.append("na pasta do jogo e FORA DA LISTA (o .bat tiraria): " + rel)
    for p in problemas:
        print(p)
    print("lista da build: %d arquivos, %d usados pelo jogo, %d problemas" % (len(lista), len(usados), len(problemas)))
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
