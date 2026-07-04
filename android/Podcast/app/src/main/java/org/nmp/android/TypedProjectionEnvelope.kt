package org.nmp.android

@OptIn(ExperimentalUnsignedTypes::class)
data class TypedProjectionEnvelope(
    val key: String,
    val schemaId: String,
    val schemaVersion: UInt,
    val fileIdentifier: String,
    val payload: ByteArray,
    val projectionRev: ULong,
    val state: UByte,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TypedProjectionEnvelope) return false
        return key == other.key &&
            schemaId == other.schemaId &&
            schemaVersion == other.schemaVersion &&
            fileIdentifier == other.fileIdentifier &&
            payload.contentEquals(other.payload) &&
            projectionRev == other.projectionRev &&
            state == other.state
    }

    override fun hashCode(): Int {
        var result = key.hashCode()
        result = 31 * result + schemaId.hashCode()
        result = 31 * result + schemaVersion.hashCode()
        result = 31 * result + fileIdentifier.hashCode()
        result = 31 * result + payload.contentHashCode()
        result = 31 * result + projectionRev.hashCode()
        result = 31 * result + state.hashCode()
        return result
    }
}
