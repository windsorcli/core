#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# OpenEBS Component Tests
# bats file_tags=storage:block,storage:filesystem
#-----------------------------------------------------------------------------------------------------------------------

@test "CSI: Check openebs-localpv-provisioner pods" {
  check_pods_running "system-csi" "name=openebs-localpv-provisioner" 1
}

@test "CSI: Check blockdeviceclaims.openebs.io CRD version" {
  check_crd_version "blockdeviceclaims.openebs.io" "v1alpha1"
}

@test "CSI: Check blockdevices.openebs.io CRD version" {
  check_crd_version "blockdevices.openebs.io" "v1alpha1"
}

@test "CSI: Check cstorbackups.cstor.openebs.io CRD version" {
  check_crd_version "cstorbackups.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorcompletedbackups.cstor.openebs.io CRD version" {
  check_crd_version "cstorcompletedbackups.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorpoolclusters.cstor.openebs.io CRD version" {
  check_crd_version "cstorpoolclusters.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorpoolinstances.cstor.openebs.io CRD version" {
  check_crd_version "cstorpoolinstances.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorrestores.cstor.openebs.io CRD version" {
  check_crd_version "cstorrestores.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorvolumeattachments.cstor.openebs.io CRD version" {
  check_crd_version "cstorvolumeattachments.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorvolumeconfigs.cstor.openebs.io CRD version" {
  check_crd_version "cstorvolumeconfigs.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorvolumepolicies.cstor.openebs.io CRD version" {
  check_crd_version "cstorvolumepolicies.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorvolumereplicas.cstor.openebs.io CRD version" {
  check_crd_version "cstorvolumereplicas.cstor.openebs.io" "v1"
}

@test "CSI: Check cstorvolumes.cstor.openebs.io CRD version" {
  check_crd_version "cstorvolumes.cstor.openebs.io" "v1"
}

@test "CSI: Check jivavolumepolicies.openebs.io CRD version" {
  check_crd_version "jivavolumepolicies.openebs.io" "v1alpha1"
}

@test "CSI: Check jivavolumes.openebs.io CRD version" {
  check_crd_version "jivavolumes.openebs.io" "v1alpha1"
}

@test "CSI: Check lvmnodes.local.openebs.io CRD version" {
  check_crd_version "lvmnodes.local.openebs.io" "v1alpha1"
}

@test "CSI: Check lvmsnapshots.local.openebs.io CRD version" {
  check_crd_version "lvmsnapshots.local.openebs.io" "v1alpha1"
}

@test "CSI: Check lvmvolumes.local.openebs.io CRD version" {
  check_crd_version "lvmvolumes.local.openebs.io" "v1alpha1"
}

@test "CSI: Check migrationtasks.openebs.io CRD version" {
  check_crd_version "migrationtasks.openebs.io" "v1alpha1"
}

@test "CSI: Check upgradetasks.openebs.io CRD version" {
  check_crd_version "upgradetasks.openebs.io" "v1alpha1"
}

@test "CSI: Check zfsbackups.zfs.openebs.io CRD version" {
  check_crd_version "zfsbackups.zfs.openebs.io" "v1"
}

@test "CSI: Check zfsnodes.zfs.openebs.io CRD version" {
  check_crd_version "zfsnodes.zfs.openebs.io" "v1"
}

@test "CSI: Check zfsrestores.zfs.openebs.io CRD version" {
  check_crd_version "zfsrestores.zfs.openebs.io" "v1"
}

@test "CSI: Check zfssnapshots.zfs.openebs.io CRD version" {
  check_crd_version "zfssnapshots.zfs.openebs.io" "v1alpha1"
}
