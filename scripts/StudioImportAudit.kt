@file:JvmName("StudioImportAudit")
package com.cadillac.wallpaperstudio

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipFile
import javax.imageio.ImageIO

/** Compiled alongside the unmodified production importer, not a Python port. */
fun main(args: Array<String>) {
    require(args.size == 4) { "report.json library A.zip B.zip" }
    val reportFile = File(args[0])
    val library = File(args[1])
    require(!library.exists()) { "Use a fresh isolated verification library" }
    val importer = PackageImporter(library)
    val rows = JSONArray()
    val ids = mutableListOf<String>()
    for ((index, input) in args.drop(2).map(::File).withIndex()) {
        val theme = importer.import(input.inputStream(), input.name)
        ids += theme.id
        val images = JSONArray()
        val payload = if (input.extension.equals("cwtheme", ignoreCase = true)) {
            val extracted = File.createTempFile("audit-ota-", ".zip", reportFile.parentFile)
            ZipFile(input).use { outer ->
                val entry = checkNotNull(outer.getEntry("cwtheme/payload/ota_wallpaper.zip"))
                outer.getInputStream(entry).use { source ->
                    extracted.outputStream().use { target -> source.copyTo(target) }
                }
            }
            extracted
        } else input
        ZipFile(payload).use { zip ->
            val files = zip.entries().toList().filterNot { it.isDirectory }
            check(files.size == 9)
            val preview = files.single { it.name.endsWith("/light_preview_image.png") }
            val root = preview.name.removeSuffix("light_preview_image.png")
            for (entry in files) {
                val installed = File(theme.directory, entry.name.removePrefix(root))
                check(installed.isFile)
                check(installed.readBytes().contentEquals(zip.getInputStream(entry).use { it.readBytes() }))
            }
            for (night in listOf(false, true)) {
                val file = theme.preview(night)
                val image = checkNotNull(ImageIO.read(file)) { "Preview failed PNG decoding" }
                check(image.width == 2198 && image.height == 367)
                val colors = HashSet<Int>()
                for (y in 0 until image.height step 5) for (x in 0 until image.width step 5) {
                    val pixel = image.getRGB(x, y)
                    if ((pixel ushr 24) != 0) colors.add(pixel and 0xffffff)
                }
                check(colors.size > 100) { "Preview is blank or nearly constant" }
                images.put(JSONObject().put("theme", if (night) "dark" else "light")
                    .put("width", image.width).put("height", image.height)
                    .put("sha256", file.sha256()).put("sampledOpaqueColors", colors.size).put("decoded", true))
            }
        }
        check(theme.preview(true).sha256() != theme.preview(false).sha256())
        rows.put(JSONObject().put("slot", if (index == 0) "A" else "B")
            .put("input", input.name).put("inputSha256", input.sha256())
            .put("zipSha256", payload.sha256())
            .put("libraryId", theme.id).put("folder", theme.folder).put("kzbRelative", theme.kzbRelative)
            .put("kzbSha256", theme.kzb.sha256()).put("expandedBytes", theme.bytes)
            .put("importPassed", true).put("allResourcesByteIdentical", true).put("previews", images))
        if (payload != input) payload.delete()
    }
    check(ids[0] != ids[1])
    check(importer.list().size == 2)
    val a = File(args[2])
    val again = importer.import(a.inputStream(), a.name)
    check(again.id == ids[0] && importer.list().size == 2)
    val result = JSONObject().put("passed", true).put("actualImporterSourceCompiled", true)
        .put("packages", rows).put("aBAReimportStable", true)
        .put("scope", "JVM execution of production PackageImporter.kt and ThemePackage.kt, PNG decoding, exact extracted bytes; not vehicle application")
        .put("vehicleNoRestartVerified", false)
    reportFile.parentFile.mkdirs()
    reportFile.writeText(result.toString(2) + "\n")
    println("Actual PackageImporter passed: A, B, A reimport; four day/night previews decode; all nine resources per ZIP remain exact.")
}
