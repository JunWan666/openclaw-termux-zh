package com.junwan666.openclawzh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class NpmCacheManagerTest {
    @Test
    fun trimDirectoryEvictsOldestFilesFirst() {
        val directory = Files.createTempDirectory("npm-cache-test").toFile()
        try {
            val oldest = createFile(directory, "content/old", 40, 1_000)
            val middle = createFile(directory, "content/middle", 40, 2_000)
            val newest = createFile(directory, "content/new", 40, 3_000)

            assertTrue(NpmCacheManager.trimDirectory(directory, 80))
            assertFalse(oldest.exists())
            assertTrue(middle.exists())
            assertTrue(newest.exists())
            assertEquals(80, directory.walkTopDown().filter { it.isFile }.sumOf { it.length() })
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun trimDirectoryLeavesCacheWithinLimitUntouched() {
        val directory = Files.createTempDirectory("npm-cache-test").toFile()
        try {
            val cached = createFile(directory, "content/cached", 40, 1_000)
            assertFalse(NpmCacheManager.trimDirectory(directory, 40))
            assertTrue(cached.exists())
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun createFile(root: File, path: String, size: Int, modified: Long): File {
        val file = File(root, path)
        file.parentFile?.mkdirs()
        file.writeBytes(ByteArray(size) { 1 })
        file.setLastModified(modified)
        return file
    }
}
