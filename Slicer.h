#pragma once
#include <fstream>
#include <string>
#include <vector>
#include <filesystem>
#include <algorithm>
#include <iostream>

namespace fs = std::filesystem;

static void Slice(const std::string& filePath, const std::string& archivePath, int partSize_inBytes) {
    std::ifstream in(filePath, std::ios::binary | std::ios::ate);
    if (!in) {
        std::cerr << "Cannot open input file.\n";
        return;
    }

    std::streamsize totalSize = in.tellg();
    in.seekg(0, std::ios::beg);

    int partId = 0;
    std::vector<char> buffer(partSize_inBytes);

    // ... slicing
    while (totalSize > 0) {
        std::streamsize toRead = std::min<std::streamsize>(partSize_inBytes, totalSize);

        // ... reading bytes to toRead
        in.read(buffer.data(), toRead);

        std::string partFile = (fs::path(archivePath) / ("part_" + std::to_string(partId) + ".bin")).string();
        std::ofstream out(partFile, std::ios::binary);
        if (!out) {
            std::cerr << "Cannot create part file.\n";
            return;
        }

        out.write(reinterpret_cast<const char*>(&partId), sizeof(int));
        out.write(buffer.data(), toRead);
        out.close();

        totalSize -= toRead;
        partId++;
    }

    in.close();
}

static void Rebuild(const std::string& archivePath, const std::string& destinationFile) {
    std::vector<std::string> parts;

    // ... parts collecting
    for (const auto& entry : fs::directory_iterator(archivePath)) {
        if (entry.is_regular_file() && entry.path().extension() == ".bin") {
            parts.push_back(entry.path().string());
        }
    }

    if (parts.empty()) {
        std::cerr << "No parts found in: " << archivePath << "\n";
        return;
    }

    // ... sort by id
    std::sort(parts.begin(), parts.end(), [](const std::string& a, const std::string& b) {
        std::ifstream fa(a, std::ios::binary);
        std::ifstream fb(b, std::ios::binary);
        int idA = -1, idB = -1;
        fa.read(reinterpret_cast<char*>(&idA), sizeof(int));
        fb.read(reinterpret_cast<char*>(&idB), sizeof(int));
        return idA < idB;
    });

    std::ofstream out(destinationFile, std::ios::binary);
    if (!out) {
        std::cerr << "Cannot create output file.\n";
        return;
    }

    // ... reconstruction and save
    std::vector<char> buffer(1024 * 1024);
    for (const auto& part : parts) {
        std::ifstream in(part, std::ios::binary);
        int id;
        in.read(reinterpret_cast<char*>(&id), sizeof(int));
        while (in) {
            in.read(buffer.data(), buffer.size());
            std::streamsize bytesRead = in.gcount();
            if (bytesRead > 0) out.write(buffer.data(), bytesRead);
        }
        in.close();
    }

    out.close();
}
