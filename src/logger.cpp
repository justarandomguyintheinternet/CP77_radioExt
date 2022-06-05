#include <fstream>
#include <ctime>
#include <sstream>

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
    std::string getTimeString(){
        time_t now = time(0);
        tm *ltm = localtime(&now);

        return "[" + std::to_string(ltm->tm_hour) + ":" + std::to_string(ltm->tm_min) + ":" + std::to_string(ltm->tm_sec) + "]";
    }
    void log(std::string msg){
        file << getTimeString() << " [Info] " << msg << std::endl;
    }
    void engine(std::string msg){
        file << getTimeString() << " [AudioEngine] " << msg << std::endl;
    }
    void error(std::string msg){
        file << getTimeString() << " [Error] " << msg << std::endl;
    }
};