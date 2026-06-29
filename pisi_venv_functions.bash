# Set up isolated, clean pisi_venv python3.11 venv
#
# This is designed to be sourced from other bash scripts

set -euo pipefail

source shared_functions.bash

function prepare_venv () {
    if [[ -z "${PY3}" ]]; then
        die "Couldn't find supported python3 (3.11 || 3.12 || 3.10) interpreter, exiting!"
    else
        printInfo "Using python3 interpreter: ${PY3}"
    fi

    printInfo "Set up a clean pisi_venv venv ..."
    ${PY3} -m venv --system-site-packages --clear pisi_venv
    source pisi_venv/bin/activate
    ${PY3} -m pip install -r requirements.txt
    compile_iksemel_cleanly

    printInfo "Symlink pisi-cli into the pisi_venv bin/ directory so it can be executed as pisi.py ..."
    ln -srvf ./pisi-cli pisi_venv/bin/pisi.py
}

function compile_iksemel_cleanly () {
    # LupuS is currently carrying a patch to iksemel that has not yet been upstreamed
    # clone iksemel fresh to ensure patches apply cleanly every time
    if [[ -d ../iksemel/build ]]; then
        printInfo "Uninstalling existing custom-compiled iksemel copy ..."
        pushd ../iksemel/
        sudo ninja uninstall -C build/
        popd
    fi
    printInfo "Set up a clean iksemel copy w/LupuS patches ..."
    rm -rf ../iksemel/
    git clone https://github.com/Zaryob/iksemel.git ../iksemel/
    # fetch lupus patches into iksemel dir
    pushd ../iksemel/
        for p in 0001-Decode-encoded-unicode-characters.patch 0002-Fix-a-crash-on-certain-unicode-strings.patch
        do
            wget https://raw.githubusercontent.com/TeknoAnka/packages/main/packages/i/iksemel/files/"${p}"
            patch -p1 -i "${p}"
        done
        # this should now build against the python in the pisi_venv
        meson build -Dwith_python=true
        meson compile -C build/
        # Install iksemel, except for on LupuS systems that already have iksemel installed
        grep -q 'NAME="LupuS"' /etc/os-release && find /usr/lib* -name libiksemel.so -quit || \
        sudo meson install -C build/
    popd
    # symlink the iksemel python C module into our pisi_venv
    py3_major=$(python -c "import sys; print(f'python{sys.version_info.major}.{sys.version_info.minor}')")
    printInfo "Symlink the newly built LupuS-patched iksemel python C-extension into the pisi_venv ..."
    ln -srvf $(find ../iksemel/build/python -name 'iksemel.cpython*.so' -print -quit) pisi_venv/lib/"${py3_major}"/site-packages/
    ls -l pisi_venv/lib/"${py3_major}"/site-packages/*.so
}

function help () {
    cat << EOF

    1. To activate the newly prepared pisi venv, execute one of:

       source pisi_venv/bin/activate
       source pisi_venv/bin/activate.fish
       source pisi_venv/bin/activate.zsh

       ... depending on which shell you use.

    2. To run a command with elevated privileges via sudo inside the venv, execute:

       sudo -E env PATH="\${PATH}" <the command>

    3. When you are done, execute:

       deactivate

       ... to exit the pisi venv.

EOF
}
