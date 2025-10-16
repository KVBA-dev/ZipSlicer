#include "Exceptions.h"
#include "Slicer.h"
#include "SystemUtility.h"
#include <Windows.h>
#include <iostream>
#include <string>
#include <strsafe.h>

static long long ConvertToBytes(long long value, const std::string& unit) {
    if (unit == "-b")  return value;
    if (unit == "-kb") return value * 1024LL;
    if (unit == "-mb") return value * 1024LL * 1024LL;
    if (unit == "-gb") return value * 1024LL * 1024LL * 1024LL;
    return value;
}

int main(int argNum, char** args) {
    if (argNum == 1) {
        std::string currentDir = fs::current_path().string();

        if (HasBinParts(currentDir)) {
            std::string outPath = currentDir + "\\rebuilt_archive.zip";
            Rebuild(currentDir, outPath);
            std::cout << "Auto rebuilt archive: " << outPath << "\n";
            DeleteBinParts(currentDir);
            return 0;
        }

        Exceptions::show.invalidArguments();
        return 1;
    }

    if (argNum < 3) {
        Exceptions::show.invalidArguments();
        return 1;
    }

    std::string firstArg = args[1];
    std::string secondArg = args[2];
    std::string zipFile;
    std::string folderPath;


    if (ends_with(firstArg, ".zip")) {
        zipFile = firstArg;
        folderPath = secondArg;
    } else if (ends_with(secondArg, ".zip")) {
        zipFile = secondArg;
        folderPath = firstArg;
    } else {
        std::cerr << "One of the arguments has to be .zip\n";
        return 1;
    }

    bool zipExists = fs::exists(zipFile);
    bool folderExists = fs::exists(folderPath);

    if (zipExists) {
        if (argNum < 4) {
            Exceptions::show.invalidArguments();
            return 1;
        }

        long long partSize = std::stoll(args[3]);
        std::string unit = "-b";
        if (argNum >= 5) {
            unit = args[4];
        }
        partSize = ConvertToBytes(partSize, unit);

        if (!folderExists) {
            fs::create_directories(folderPath);
        }

        Slice(zipFile, folderPath, partSize);

        std::cout << "Sliced file: " << zipFile
                  << " into: " << folderPath
                  << " | part size: " << partSize << " bytes\n";
    }

    else if (folderExists && HasBinParts(folderPath)) {
        Rebuild(folderPath, zipFile);
        std::cout << "Rebuilt archive to: " << zipFile << "\n";
    }
    else {
        std::cerr << "Incorrect argument combination\n";
        return 1;
    }

    return 0;
}
