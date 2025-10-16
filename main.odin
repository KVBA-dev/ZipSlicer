package main

import "core:fmt"
import os "core:os/os2"
import fp "core:path/filepath"
import sl "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"

SizeParserState :: enum {
	Start,
	Number,
	Unit,
}

SizeParserError :: enum {
	InvalidString,
	InvalidUnit,
}

parse_file_size :: proc(filesize: string) -> (size: i64, err: SizeParserError) {
	size = 0
	state: SizeParserState = .Start
	for c in filesize {
		switch state {
		case .Start:
			if c >= '0' && c <= '9' {
				state = .Number
				size = i64(c - '0')
			} else {
				return 0, .InvalidString
			}
		case .Number:
			if c >= '0' && c <= '9' {
				size = size * 10 + i64(c - '0')
			} else if c == 'k' || c == 'K' {
				size *= 1024
				state = .Unit
			} else if c == 'm' || c == 'M' {
				size *= 1024 * 1024
				state = .Unit
			} else if c == 'g' || c == 'G' {
				size *= 1024 * 1024 * 1024
				state = .Unit
			} else if c == 't' || c == 'T' {
				size *= 1024 * 1024 * 1024 * 1024
				state = .Unit
			} else {
				return 0, .InvalidString
			}
		case .Unit:
			return 0, .InvalidUnit
		}
	}
	return size, nil

}

main :: proc() {
	if len(os.args) == 1 {
		currdir := fp.dir(os.args[0], context.temp_allocator)
		if has_zip_parts(currdir) {
			outpath := fp.join([]string{currdir, "rebuilt_archive.zip"})
			rebuild(currdir, outpath)
			fmt.println("Auto rebuild archive:", outpath)
			delete_zip_parts(currdir)
			os.exit(0)
		}

		show_invalid_arguments()
		os.exit(1)
	}

	if len(os.args) < 3 {
		show_invalid_arguments()
		os.exit(1)
	}

	ensure(len(os.args) == 4, "too many arguments")

	firstArg := os.args[1]
	secondArg := os.args[2]
	zipfile: string
	dirpath: string

	if firstArg != "-r" {
		if fp.ext(firstArg) == ".zip" {
			zipfile = firstArg
			dirpath = secondArg
		} else if fp.ext(secondArg) == ".zip" {
			zipfile = secondArg
			dirpath = firstArg
		} else {
			fmt.println("One of the arguments has to be .zip")
			os.exit(1)
		}
	} else {
		dirpath = os.args[2]
		zipfile = os.args[3]
	}

	zipexists := os.is_file(zipfile)
	direxists := os.is_dir(dirpath)

	if zipexists && zipfile == firstArg {
		if len(os.args) < 4 {
			show_invalid_arguments()
			os.exit(1)
		}

		partsize, parserr := parse_file_size(os.args[3])
		if parserr != nil {
			fmt.println("Invalid part size")
			os.exit(1)
		}

		slice(zipfile, dirpath, partsize)

		fmt.println("Sliced file:", zipfile, "into:", dirpath, "| part size:", partsize, "B")
	} else if direxists && has_zip_parts(dirpath) {
		rebuild(dirpath, zipfile)
		fmt.println("Rebuilt archive to:", zipfile)
	} else {
		show_invalid_arguments()
		os.exit(1)
	}
}

PART_EXTENSION :: ".pzi"

show_invalid_arguments :: proc() {
	msg :: `
=== [ USAGE ] ===
Slice:   FileSlicer [archive path] [destination directory] [size with unit]
    or   FileSlicer [destination directory] [archive path] [size with unit]

	Example size values:
	 - 500 = 500 bytes
	 - 500k = 500 kilobytes
	 - 500m = 500 megabytes
	 - 500g = 500 gigabytes
	 - 500t = 500 terabytes
	Unit is case-insensitive (50k and 50K are the same size)

Example: FileSlicer my.zip parts 10m
-----------------------
Rebuild: FileSlicer -r [directory with parts] [destination archive path]
         or just run FileSlicer.exe in a folder with .bin files to auto rebuild
`


	fmt.println(msg)
}

has_zip_parts :: proc(dirpath: string, allocator := context.allocator) -> bool {
	dir, err := os.open(dirpath)
	defer os.close(dir)
	if err != nil {
		return false
	}
	files, readerr := os.read_dir(dir, 0, allocator)
	defer os.file_info_slice_delete(files, allocator)
	if readerr != nil {
		return false
	}
	for fi in files {
		if fi.type == .Regular && fp.ext(fi.fullpath) == PART_EXTENSION {
			when ODIN_DEBUG {
				fmt.println("Found a file with given extension:", fi.fullpath)
			}
			return true
		}
	}
	return false
}

sort_parts_by_id :: proc(i, j: os.File_Info) -> bool {
	fi, fierr := os.open(i.fullpath)
	fj, fjerr := os.open(j.fullpath)
	defer {
		os.close(fi)
		os.close(fj)
	}
	if fierr != nil || fjerr != nil {
		return false
	}

	bi := [4]u8{}
	bj := [4]u8{}
	_, err := os.read_at(fi, bi[:], 0)
	_, err = os.read_at(fj, bj[:], 0)

	return transmute(i32)bi < transmute(i32)bj
}

rebuild :: proc(dirpath, zipfile: string, allocator := context.allocator) {
	parts := make([dynamic]os.File_Info)
	defer delete(parts)

	files: []os.File_Info

	{
		dir, err := os.open(dirpath)
		defer os.close(dir)
		if err != nil {
			return
		}
		files, err = os.read_dir(dir, 0, allocator)
		if err != nil {
			return
		}
	}
	defer os.file_info_slice_delete(files, allocator)
	for fi in files {
		when ODIN_DEBUG {
			fmt.println("examining", fi.fullpath)
		}
		if fi.type == .Regular && fp.ext(fi.fullpath) == PART_EXTENSION {
			when ODIN_DEBUG {
				fmt.println("adding", fi.fullpath)
			}
			append(&parts, fi)
		}
	}
	partslice := parts[:len(parts)]
	sl.sort_by(partslice, sort_parts_by_id)

	when ODIN_DEBUG {
		fmt.println("sorted files:")
		for fi in parts {
			fmt.println(fi.name)
		}
	}

	outfile, outerr := os.open(zipfile, os.File_Flags{.Write, .Create})
	defer os.close(outfile)
	if outerr != nil {
		fmt.println("Could not create file", zipfile, "-", outerr)
		return
	}

	for fi in partslice {
		when ODIN_DEBUG {
			fmt.println("Reading from", fi.fullpath, "...")
		}
		data, err := os.read_entire_file_from_path(fi.fullpath, allocator)
		defer delete(data, allocator)
		if err != nil {
			fmt.println("Could not read file", fi.fullpath, "-", err)
			return
		}

		if len(data) <= 4 {
			continue
		}

		_, err = os.write(outfile, data[4:])
		if err != nil {
			fmt.println("Could not write to file", outfile, "-", err)
			return
		}
	}

}

delete_zip_parts :: proc(dirpath: string, allocator := context.allocator) {
	dir, err := os.open(dirpath)
	defer os.close(dir)
	if err != nil {
		return
	}
	files, readerr := os.read_dir(dir, 0, allocator)
	defer delete(files, allocator)
	if readerr != nil {
		return
	}
	for fi in files {
		if fi.type == .Regular && fp.ext(fi.fullpath) == PART_EXTENSION {
			rmerr := os.remove(fi.fullpath)
			if rmerr != nil {
				fmt.println("Could not remove", fi.name, "-", rmerr)
			}
		}
	}
}

slice :: proc(zipfile, dirpath: string, partsize: i64, allocator := context.allocator) {
	abspath, pathok := fp.abs(zipfile, allocator)
	defer delete(abspath)
	if !pathok {
		fmt.println("Could not derive abs path to", zipfile)
		return
	}

	fd, fileerr := os.open(zipfile)
	defer os.close(fd)

	if fileerr != nil {
		fmt.println("Could not open file", zipfile, "-", fileerr)
		return
	}

	offset: i64 = 0
	partid: i32 = 0

	buf := make([]u8, partsize, allocator)
	defer delete(buf, allocator)


	for {
		bytesread, readerr := os.read_at(fd, buf, offset)
		if readerr != nil && readerr != .EOF {
			fmt.println("Could not read file", zipfile, "-", readerr)
			return
		}
		offset += partsize
		part := buf[:bytesread]
		when ODIN_DEBUG {
			fmt.println("bytes read:", bytesread)
		}

		partname: string
		partname, fileerr = strings.concatenate(
			[]string {
				fp.join([]string{dirpath, fp.base(zipfile)}, context.temp_allocator),
				fmt.tprintf("_part_%d", partid),
				PART_EXTENSION,
			},
			context.temp_allocator,
		)

		if fileerr != nil {
			fmt.println("Error on creating file name -", fileerr)
			return
		}

		partfile, fileerr := os.open(partname, os.File_Flags{.Write, .Create})
		defer os.close(partfile)
		if fileerr != nil {
			fmt.println("Could not create file", partname, "-", fileerr)
			return
		}

		bufid := transmute([4]u8)partid

		byteswritten, writeerr := os.write(partfile, bufid[:])
		assert(byteswritten == 4, "write error")
		if writeerr != nil {
			fmt.println("Could not write to file", partname, "-", writeerr)
		}


		byteswritten, writeerr = os.write(partfile, part[:])
		assert(byteswritten == len(part), "write error")
		if writeerr != nil {
			fmt.println("Could not write to file", partname, "-", writeerr)
		}

		partid += 1
		if i64(bytesread) < partsize {
			break
		}
	}
}
