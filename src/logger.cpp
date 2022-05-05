#include <fstream>
#include <ctime>

class logger {
private:
    std::ofstream file;

public:
    logger(std::string fileName){
        file = std::ofstream(fileName, std::ios::app);
    }
    ~logger() {
        if (file.is_open()){
            file.close();
        }
    }
    void log(std::string msg){
        time_t now = time(0);
        tm *ltm = localtime(&now);

        file << "[" << ltm->tm_hour << ":" << ltm->tm_min << ":" << ltm->tm_sec << "]" << " " << msg << std::endl;
    }
};