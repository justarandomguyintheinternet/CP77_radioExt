#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <Windows.h>
#include <fstream>
#include <thread>
#include <chrono>
#include <atomic>
#include <mutex>
#include <filesystem>
#include "logger.cpp"
#include "json.hpp"
#include <string>
#include <random>
#include <malloc.h>