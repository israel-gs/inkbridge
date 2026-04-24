package com.inkbridge.protocol

/**
 * Thrown by [BinaryStylusCodec.decode] when the input byte array violates the
 * InkBridge wire protocol v1 contract (wire-protocol.md R2, R4, R8).
 *
 * @param message Human-readable description of the violation.
 */
class ProtocolException(message: String) : Exception(message)
