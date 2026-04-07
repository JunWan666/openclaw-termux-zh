package com.junwan666.openclawzh

import java.io.File

object HostFilesystem {
    fun ensureDirectoryReady(path: String, label: String): File {
        val dir = File(path)
        val parent = dir.parentFile

        if (parent != null && parent.exists() && !parent.isDirectory) {
            throw IllegalStateException(
                "$label parent is not a directory: ${parent.absolutePath}"
            )
        }

        if (dir.exists() && !dir.isDirectory) {
            if (!dir.delete()) {
                throw IllegalStateException(
                    "Expected $label to be a directory, but found a file at ${dir.absolutePath} that could not be removed"
                )
            }
        }

        if (!dir.exists() && !dir.mkdirs() && !dir.isDirectory) {
            throw IllegalStateException("Failed to create $label at ${dir.absolutePath}")
        }

        if (!dir.isDirectory) {
            throw IllegalStateException("$label is not a directory: ${dir.absolutePath}")
        }

        dir.setReadable(true, false)
        dir.setWritable(true, false)
        dir.setExecutable(true, false)
        return dir
    }

    fun ensureFileTargetReady(path: String, label: String): File {
        val file = File(path)
        val parent = file.parentFile
            ?: throw IllegalStateException("$label has no parent directory: ${file.absolutePath}")

        ensureDirectoryReady(parent.absolutePath, "$label parent directory")

        if (file.exists() && file.isDirectory) {
            if (!file.deleteRecursively()) {
                throw IllegalStateException(
                    "Expected $label to be a file, but found a directory at ${file.absolutePath} that could not be removed"
                )
            }
        }

        return file
    }

    fun describePathState(path: String): String {
        val file = File(path)
        val parent = file.parentFile
        val parentExists = parent?.exists() == true
        val parentIsDirectory = parent?.isDirectory == true

        return buildString {
            append("path=")
            append(file.absolutePath)
            append(", exists=")
            append(file.exists())
            append(", isDirectory=")
            append(file.isDirectory)
            append(", isFile=")
            append(file.isFile)
            append(", canRead=")
            append(file.canRead())
            append(", canWrite=")
            append(file.canWrite())
            append(", parentExists=")
            append(parentExists)
            append(", parentIsDirectory=")
            append(parentIsDirectory)
        }
    }
}
