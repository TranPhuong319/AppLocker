#include <iostream>
#include <vector>
#include <cstring>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <Security/Authorization.h>
#include <Security/Security.h>

bool file_exists(const std::string &path) {
    return access(path.c_str(), F_OK) == 0;
}

// Hàm chạy lệnh có quyền root thông qua Authorization
bool runWithPrivileges(AuthorizationRef authRef, const std::string& tool, const std::vector<std::string>& arguments) {
    char *args[arguments.size() + 1];
    for (size_t i = 0; i < arguments.size(); ++i) {
        args[i] = const_cast<char*>(arguments[i].c_str());
    }
    args[arguments.size()] = nullptr;

    FILE* pipe = nullptr;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = AuthorizationExecuteWithPrivileges(authRef, tool.c_str(), kAuthorizationFlagDefaults, args, &pipe);
#pragma clang diagnostic pop

    if (status != errAuthorizationSuccess) {
        std::cerr << "AuthorizationExecuteWithPrivileges failed\n";
        return false;
    }

    if (pipe) {
        char buffer[128];
        while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
            // có thể in ra output nếu cần
        }
        fclose(pipe);
    }

    return true;
}

bool make_executable(AuthorizationRef authRef, const std::string& path) {
    return runWithPrivileges(authRef, "/bin/chmod", {"0500", path});
}

bool remove_executable(AuthorizationRef authRef, const std::string& path) {
    return runWithPrivileges(authRef, "/bin/chmod", {"0000", path});
}

int main(int argc, char *argv[]) {
    std::string selfPath = argv[0];
    std::string realPath = selfPath + ".real";

    if (!file_exists(realPath)) {
        std::cerr << "App is not locked. Nothing to launch.\n";
        return 1;
    }

    // Step 1: Xác thực người dùng
    AuthorizationRef authRef = nullptr;
    OSStatus status = AuthorizationCreate(nullptr,
                                          kAuthorizationEmptyEnvironment,
                                          kAuthorizationFlagDefaults,
                                          &authRef);
    if (status != errAuthorizationSuccess) return 1;

    AuthorizationItem right = {kAuthorizationRightExecute, 0, nullptr, 0};
    AuthorizationRights rights = {1, &right};
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                                kAuthorizationFlagExtendRights;

    status = AuthorizationCopyRights(authRef, &rights, nullptr, flags, nullptr);
    if (status != errAuthorizationSuccess) return 1;

    // Step 2: Cấp quyền thực thi cho file gốc
    if (!make_executable(authRef, realPath)) {
        std::cerr << "chmod +x failed\n";
        return 1;
    }

    // Step 3: fork và exec file gốc
    pid_t pid = fork();
    if (pid == -1) {
        perror("fork failed");
        return 1;
    } else if (pid == 0) {
        std::vector<char*> newArgs;
        newArgs.push_back(const_cast<char*>(realPath.c_str())); // argv[0] là file .real

        for (int i = 1; i < argc; ++i) {
            newArgs.push_back(argv[i]); // giữ nguyên từng argv
        }

        newArgs.push_back(nullptr);

        // Chạy file gốc với toàn bộ tham số gốc
        execv(realPath.c_str(), newArgs.data());

        perror("execv failed");
        _exit(1);
    } else {
        // Parent: đợi tiến trình con
        int status_code = 0;
        waitpid(pid, &status_code, 0);

        // Step 4: thu hồi quyền thực thi sau khi chạy xong
        if (!remove_executable(authRef, realPath)) {
            std::cerr << "chmod 0000 failed\n";
            return 1;
        }

        return WIFEXITED(status_code) ? WEXITSTATUS(status_code) : 1;
    }
}
