// warden-list: fast replacement for the pure-bash `listKeys` (see utils.sh).
//
// Reads every file in WARDEN_DIRECTORY (skipping master.md), pulls the title
// (line 1), hashtags (line 2) and timestamp (last line), sorts entries ascending
// by timestamp, and prints them in exactly the same colored format the old bash
// loop produced. The bash version did this with an O(n^2) insertion sort that
// forked an `expr` for every arithmetic op; this is O(n log n) with no subprocesses.

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <dirent.h>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

// Mirrors config.sh / colors.sh so output stays byte-identical to the bash version.
static const std::string ENCRYPTED_ROW = "--ENCRYPTED--";
static const std::string Cyan = "\033[0;36m";
static const std::string Purple = "\033[0;35m";
static const std::string Color_Off = "\033[0m";

struct Entry {
    int64_t timestamp;  // sort key (last line, parsed as integer)
    std::string display;
};

int main(int argc, char** argv) {
    // Directory comes from argv[1], falling back to the WARDEN_DIRECTORY env var
    // so the binary can be used the same way the bash code referenced the variable.
    std::string dir;
    if (argc > 1) {
        dir = argv[1];
    } else if (const char* env = std::getenv("WARDEN_DIRECTORY")) {
        dir = env;
    } else {
        std::cerr << "WARDEN_DIRECTORY not provided\n";
        return 1;
    }

    DIR* dp = opendir(dir.c_str());
    if (!dp) {
        std::cerr << "Cannot open directory: " << dir << "\n";
        return 1;
    }

    // Collect filenames first and sort alphabetically, matching `ls` order. This
    // only affects ties (entries with equal timestamps), where std::stable_sort
    // below preserves it -- same as the stable bash insertion sort.
    std::vector<std::string> names;
    for (struct dirent* de; (de = readdir(dp)) != nullptr;) {
        std::string name = de->d_name;
        if (name == "." || name == "..") continue;
        names.push_back(std::move(name));
    }
    closedir(dp);
    std::sort(names.begin(), names.end());

    std::vector<Entry> entries;
    entries.reserve(names.size());

    for (const auto& key : names) {
        if (key == "master.md") continue;

        std::ifstream in(dir + "/" + key);
        if (!in) continue;

        std::string title;       // line 1
        std::string hashtags;    // line 2
        std::string lastLine;    // becomes the timestamp
        std::string line;
        size_t lineNo = 0;
        while (std::getline(in, line)) {
            if (lineNo == 0) title = line;
            else if (lineNo == 1) hashtags = line;
            lastLine = line;
            ++lineNo;
        }

        if (hashtags == ENCRYPTED_ROW) hashtags = "";

        int64_t ts = 0;
        try {
            ts = std::stoll(lastLine);
        } catch (...) {
            ts = 0;  // non-numeric last line sorts as 0, like an empty bash compare
        }

        // Same layout as utils.sh:47
        //   "${Cyan}- $key ${Color_Off}$title ${Purple}$hashtags${Color_Off}"
        std::string display;
        display.append(Cyan).append("- ").append(key).append(" ").append(Color_Off);
        display.append(title).append(" ").append(Purple).append(hashtags).append(Color_Off);

        entries.push_back({ts, std::move(display)});
    }

    std::stable_sort(entries.begin(), entries.end(),
                     [](const Entry& a, const Entry& b) { return a.timestamp < b.timestamp; });

    std::string out;
    for (const auto& e : entries) {
        out += e.display;
        out += '\n';
    }
    std::cout << out;
    return 0;
}
