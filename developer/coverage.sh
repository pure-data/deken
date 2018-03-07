#!/bin/sh

deken_username=${DEKEN_USERNAME:-${USER}}
unset DEKEN_USERNAME

VE=$(mktemp -d)
VDATA="${VE}/data"
mkdir -p "${VDATA}"

teardown() {
    test -d "${VE}" && rm -rf "${VE}"
    exit $1
}

makedata() {
    # get some externals
    curl -fsSL -o "${VDATA}/deken-test.zip" "https://puredata.info/Members/zmoelnig/tests/deken-test.zip" || teardown
    unzip -d "${VDATA}/" "${VDATA}/deken-test.zip"

    touch "${VDATA}/bla.dek"
    touch "${VDATA}/bla[v000].dek"
    touch "${VDATA}/nosource(Linux-amd64-32).dek"
    touch "${VDATA}/bla[v000](Linux-amd64-32).dek"

    touch "${VDATA}/options[flub].dek"
    touch "${VDATA}/foo-externals.zip"
    touch "${VDATA}/foo--externals.zip"
    touch "${VDATA}/foo-externals.tar.gz"
    touch "${VDATA}/foo--externals.tgz"
    touch "${VDATA}/foo[v1[2]].dek"
    touch "${VDATA}/foo.zip"
    touch "${VDATA}/frobnozzel.ko"
    mkdir "${VDATA}/empty.dir/"
}

runtests() {
    ${PY}
    ${PY} -h
    DEKEN_VERSION=1.2.3 ${PY} --version

    # test all sub-commands
    ${PY} update
    ${PY} upgrade
    ${PY} install
    ${PY} package
    ${PY} upload

    # test packaging
    ${PY} package "${VDATA}/deken-test"
    ${PY} package --version 000 "${VDATA}/deken-test"
    ${PY} package -v 000 --dekformat 1 "${VDATA}/deken-test"
    ${PY} package -v 000 --dekformat 3 "${VDATA}/deken-test"
    ${PY} package -v 000 --dekformat bla "${VDATA}/deken-test"

    for f in "${VDATA}/*.*"; do
        ${PY} package --version 000 "${f}"
    done

    # test uploading
    ${PY} upload deken-test*.dek
    DEKEN_USERNAME=${deken_username} ${PY} upload  --version 000 "${VDATA}/deken-test"
    ${PY} upload "${VDATA}/bla.dek"
    ${PY} upload --no-source-error "${VDATA}"/nosource*.dek
    ${PY} upload --ask-password "${VDATA}/bla.dek"
    ${PY} upload --destination https://example.com/%u "${VDATA}/bla.dek"
    DEKEN_USERNAME=${deken_username} ${PY} upload --destination /Members/${deken_username}/software/tmp/ "${VDATA}/bla.dek"
    ${PY} upload "${VDATA}/options[flub].dek"
    ${PY} upload "${VDATA}/frobnozzel.ko"
    ${PY} upload --dekformat 1 --version 000 "${VDATA}/empty.dir"

}

covconf() {
cat <<EOF
[run]
plugins = hy_coverage_plugin
EOF
}

fixeasywebdav() {
cat >"${VE}/fix_easywebdav.py" <<EOF
def easywebdav2_patch1():
    try:
        import easywebdav2
        print("trying to fix 'easywebdav2'")
        A="""            for dir_ in dirs:\n                try:\n                    self.mkdir(dir, safe=True, **kwargs)"""
        B="""            for dir_ in dirs:\n                try:\n                    self.mkdir(dir_, safe=True, **kwargs)"""

        filename = os.path.join(os.path.dirname(easywebdav2.__file__), 'client.py')
        print(filename)
        with open(filename, "r") as f:
            data = f.read()
        data = data.replace(A, B)
        with open(filename, "w") as f:
            f.write(data)
    except Exception as e:
        print("FAILED to patch 'easywebdav2', continuing anyhow...\n %s" % (e))
easywebdav2_patch1()
EOF
python "${VE}/fix_easywebdav.py"
}


virtualenv "$@" "${VE}" || teardown $?
. "${VE}/bin/activate"

pip install -r requirements.txt
pip install coverage
PY="$(which python) pydeken.py"
COVERAGE=$(which coverage)
if [ "x${COVERAGE}" != "x" ]; then
    git clone https://github.com/timmartin/hy-coverage "${VE}/hy-coverage" \
        && (cd "${VE}/hy-coverage" && python setup.py install)
    covconf > "${VE}/coveragerc"
    "${COVERAGE}" erase
    PY="${COVERAGE} run --rcfile ${VE}/coveragerc -a --include deken*.hy pydeken.py -vvv"
fi
echo "PY: $PY"


fixeasywebdav
makedata
runtests

if [ "x${COVERAGE}" != "x" ]; then
    "${COVERAGE}" report --rcfile ${VE}/coveragerc
    "${COVERAGE}" html --rcfile ${VE}/coveragerc -d coverage
fi

teardown
