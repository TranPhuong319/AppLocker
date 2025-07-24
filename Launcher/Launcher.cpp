// Launcher.cpp

#include <iostream>
#include <vector>
#include <cstring>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <pwd.h>
#include <Security/Authorization.h>
#include <Security/Security.h>

bool file_exists(const std::string &path) {
    return access(path.c_str(), F_OK) == 0;
}

bool make_executable(const std::string &path) {
    return chmod(path.c_str(), 0500) == 0; // r-x------
}

bool remove_executable(const std::string &path) {
    return chmod(path.c_str(), 0000) == 0; // no permissions
}

int main(int argc, char *argv[]) {
    std::string selfPath = argv[0];
    std::string realPath = selfPath + ".real";

    if (!file_exists(realPath)) {
        std::cerr << "App is not locked. Nothing to launch.\n";
        return 1;
    }

    // Step 1: Ask for Authorization (passcode or biometric)
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

    // Step 2: Temporarily grant execute permission
    if (!make_executable(realPath)) {
        perror("chmod +x failed");
        return 1;
    }

    // Step 3: Fork and exec
    pid_t pid = fork();
    if (pid == -1) {
        perror("fork failed");
        return 1;
    } else if (pid == 0) {
        // Child process: launch the real app
        std::vector<char*> newArgs;
        newArgs.push_back(argv[0]); // preserve original argv[0]
        for (int i = 1; i < argc; ++i)
            newArgs.push_back(argv[i]);
        newArgs.push_back(nullptr);
        execv(realPath.c_str(), newArgs.data());
        perror("execv failed");
        _exit(1);
    } else {
        // Parent process: wait for child
        int status_code = 0;
        waitpid(pid, &status_code, 0);

        // Step 4: Revoke execute permission again
        if (!remove_executable(realPath)) {
            perror("chmod 0000 failed");
            return 1;
        }
        return WIFEXITED(status_code) ? WEXITSTATUS(status_code) : 1;
    }
}


