#!/bin/bash
#
# This is a script that will wait for CSRs to be submitted by OCP worker nodes,
# and will then approve them, based on the input given as parameters.
#
# Parameters:
#   $1 = openshift binary path
#   $2 = cluster runtime information directory
#   $3... = the names of workers to approve
#
# NOTE: Yes, yes, I know this could have been done way better but it's 2:30am.
if [ -n "$1" ]; then
    OC="$1"
    shift
else
    echo "FATAL: not enough parameters!"
    exit 1
fi

if [ -n "$1" ]; then
    CRT="$1"
    QC="${CRT}/auth/kubeconfig"
    shift
else
    echo "FATAL: not enough parameters!"
    exit 1
fi

if [ ! -d "${CRT}" ]; then
    echo "FATAL: not a directory: ${CRT}"
    exit 1
fi
if [ ! -e "${QC}" ]; then
    echo "FATAL: kubeconfig not found: ${QC}"
    exit 1
fi

CMD="${OC} --kubeconfig=${QC}"

WORKERS="$*"
WORKERS="${WORKERS#[}"
WORKERS="${WORKERS%]}"
WORKERS="${WORKERS//,}"

echo "Using ${OC} and ${QC} to approve:"
for wrk in ${WORKERS}; do
    wrk="${wrk#u}"
    echo " - ${wrk}"
done

# Wait up to LIMIT * WAIT seconds for all CSRs to appear
LIMIT=120
WAIT=10
ITER=0
while [ "$(${CMD} get csr | grep Pending | grep :node-bootstrapper | wc -l | tr -d '[[:space:]]')" != "$(echo ${WORKERS} | wc -w | tr -d '[[:space:]]')" ]; do
    ITER=$((ITER + 1))
    if [ ${ITER} -gt ${LIMIT} ]; then
	break
    fi

    FOUND="$(${CMD} get csr | grep Pending | grep :node-bootstrapper | wc -l | tr -d '[[:space:]]')"
    EXPECT="$(echo ${WORKERS} | wc -w | tr -d '[[:space:]]')"

    echo "Waiting for all pending bootstrap CSRs to show up... (${ITER}/${LIMIT}) - found ${FOUND}, expecting ${EXPECT}"
    sleep ${WAIT}
done
 TODO: see if we timed out, see if FOUND == EXPECT, etc.

echo "Got the following CSRs:"
${CMD} get csr | grep Pending | grep :node-bootstrapper

# Approve the first batch.
${CMD} get csr | grep Pending | grep :node-bootstrapper | awk '{ print $1 }' | xargs ${CMD} adm certificate approve

# Wait up to LIMIT * WAIT seconds for all CSRs to appear
LIMIT=120
WAIT=10
ITER=0
while [ "$(${CMD} get csr | grep Pending | grep system:node: | wc -l | tr -d '[[:space:]]')" != "$(echo ${WORKERS} | wc -w | tr -d '[[:space:]]')" ]; do
    ITER=$((ITER + 1))
    if [ ${ITER} -gt ${LIMIT} ]; then
	break
    fi

    FOUND="$(${CMD} get csr | grep Pending | grep system:node: | wc -l | tr -d '[[:space:]]')"
    EXPECT="$(echo ${WORKERS} | wc -w | tr -d '[[:space:]]')"

    echo "Waiting for all pending node CSRs to show up... (${ITER}/${LIMIT}) - found ${FOUND}, expecting ${EXPECT}"
    sleep ${WAIT}
done
# TODO: see if we timed out, see if FOUND == EXPECT, etc.

echo "Got the following CSRs:"
${CMD} get csr | grep Pending | grep system:node:

# Approve the second batch, worker by worker.
ERRORS=0
DID=0
for wrk in ${WORKERS}; do
    wrk="${wrk#u}"
    echo "Trying to approve ${wrk}..."

    WRK_CSR="$(${CMD} get csr | grep Pending | grep system:node:${wrk} | awk '{ print $1 }')"
    if [ -z "${WRK_CSR}" ]; then
	echo "ERROR: found CSRs, but not for ${wrk}"
	ERRORS=$((ERRORS + 1))
	continue
    fi

    ${CMD} get csr | grep Pending | grep system:node:${wrk} | awk '{ print $1 }' | xargs ${CMD} adm certificate approve
    DID=$((DID + 1))
done

echo "Approved ${DID} CSRs!"

if [ ${ERRORS} -ne 0 ]; then
    echo "ERROR: Too bad. Try next time."
    exit 1
fi

# End of approve-workers.sh
