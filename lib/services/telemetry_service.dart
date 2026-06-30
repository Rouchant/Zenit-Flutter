import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SystemSpecs {
  final String brand;
  final String model;
  final String processor;
  final int cores;
  final int threads;
  final String gen;
  final String vendor;
  final String ram;
  final String ramType;
  final String gpu;
  final String storage;
  final String display;
  final String os;

  SystemSpecs({
    required this.brand,
    required this.model,
    required this.processor,
    required this.cores,
    required this.threads,
    required this.gen,
    required this.vendor,
    required this.ram,
    required this.ramType,
    required this.gpu,
    required this.storage,
    required this.display,
    required this.os,
  });

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'model': model,
        'processor': processor,
        'cores': cores,
        'threads': threads,
        'gen': gen,
        'vendor': vendor,
        'ram': ram,
        'ramType': ramType,
        'gpu': gpu,
        'storage': storage,
        'display': display,
        'os': os,
      };

  factory SystemSpecs.fromJson(Map<String, dynamic> json) {
    return SystemSpecs(
      brand: json['brand'] ?? 'PC Genérico',
      model: json['model'] ?? 'PC Desktop',
      processor: json['processor'] ?? 'Procesador Genérico',
      cores: json['cores'] ?? 4,
      threads: json['threads'] ?? 8,
      gen: json['gen'] ?? 'Desconocida',
      vendor: json['vendor'] ?? 'Generic',
      ram: json['ram'] ?? '8GB',
      ramType: json['ramType'] ?? 'DDR4',
      gpu: json['gpu'] ?? 'Gráficos Integrados',
      storage: json['storage'] ?? '512GB SSD',
      display: json['display'] ?? '1920 x 1080 (Full HD)',
      os: json['os'] ?? 'Windows 11',
    );
  }
}

class TelemetryService {
  SystemSpecs? _cachedSpecs;

  Future<SystemSpecs> getSystemSpecs() async {
    if (_cachedSpecs != null) return _cachedSpecs!;

    if (!Platform.isWindows) {
      return _cachedSpecs = _getDefaultFallback();
    }

    try {
      final script = r'''
        $ProgressPreference = 'SilentlyContinue'
        
        # 1. CPU Info
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cpuName = ($cpu.Name -replace '\(R\)|\(TM\)', '').Trim() -replace '\s+', ' '
        $cores = $cpu.NumberOfCores
        $threads = $cpu.NumberOfLogicalProcessors

        # 2. Motherboard & Model Info
        $comp = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model
        $board = Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product
        
        $brand = $comp.Manufacturer.Trim()
        $model = $comp.Model.Trim()
        
        # Clean common virtual machine indicators
        if ($brand -match 'VirtualBox' -or $model -match 'VirtualBox') {
          $brand = 'VirtualBox'
          $model = 'Virtual Machine'
        }

        # 3. GPU Info
        $gpus = Get-CimInstance Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
        
        # 4. Memory Info
        $physMem = Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity, SMBIOSMemoryType, Speed
        $totalBytes = 0
        $physMem | ForEach-Object { $totalBytes += $_.Capacity }
        
        # 5. Disk Storage
        $disks = Get-CimInstance Win32_DiskDrive | Where-Object { $_.MediaType -notlike "*USB*" -and $_.Size -gt 0 }
        $totalStorageBytes = 0
        $disks | ForEach-Object { $totalStorageBytes += $_.Size }

        # 6. Operating System Info
        $osObj = Get-CimInstance Win32_OperatingSystem | Select-Object Caption
        $osName = ($osObj.Caption -replace 'Microsoft ', '').Trim()

        # Build output structure
        $out = @{
          brand = $brand
          model = $model
          boardBrand = $board.Manufacturer.Trim()
          boardProduct = $board.Product.Trim()
          cpu = $cpuName
          cores = $cores
          threads = $threads
          gpus = ($gpus | ForEach-Object { $_.Name })
          resWidth = ($gpus | ForEach-Object { $_.CurrentHorizontalResolution })
          resHeight = ($gpus | ForEach-Object { $_.CurrentVerticalResolution })
          resRefresh = ($gpus | ForEach-Object { $_.CurrentRefreshRate })
          ramTotal = $totalBytes
          ramType = ($physMem | ForEach-Object { $_.SMBIOSMemoryType })
          ramSpeed = ($physMem | ForEach-Object { $_.Speed })
          storageTotal = $totalStorageBytes
          os = $osName
        }
        $out | ConvertTo-Json
      ''';

      final result = await Process.run('powershell', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', script]);
      if (result.exitCode == 0) {
        final Map<String, dynamic> raw = jsonDecode(result.stdout);
        
        // Brand & Model sanitization
        String brandClean = _cleanBrandName(raw['brand'] ?? '');
        String modelClean = raw['model'] ?? '';
        if (_isGenericInfo(brandClean, modelClean)) {
          brandClean = _cleanBrandName(raw['boardBrand'] ?? 'PC Generico');
          modelClean = (raw['boardProduct'] ?? 'PC Desktop').trim();
        }
        modelClean = _refineModelName(brandClean, modelClean);

        // CPU Vendor & Generation
        final cpuName = raw['cpu'] ?? '';
        final vendor = cpuName.contains('Intel') ? 'Intel' : (cpuName.contains('AMD') ? 'AMD' : (cpuName.toLowerCase().contains('snapdragon') || cpuName.toLowerCase().contains('qualcomm') ? 'Snapdragon' : 'Generic'));
        final gen = _detectCpuGeneration(cpuName);

        // RAM capacité & type
        final totalMemoryBytes = raw['ramTotal'] ?? 0;
        final ramDisplay = _getRamDisplay(totalMemoryBytes);
        
        final List<dynamic> memoryTypes = raw['ramType'] is List ? raw['ramType'] : [raw['ramType']];
        final List<dynamic> memorySpeeds = raw['ramSpeed'] is List ? raw['ramSpeed'] : [raw['ramSpeed']];
        
        final ramTypeDisplay = _detectRamType(memoryTypes, memorySpeeds);

        // GPU Selection
        final List<dynamic> gpuList = raw['gpus'] is List ? raw['gpus'] : [raw['gpus']];
        String gpuClean = _detectBestGpu(gpuList.cast<String>());

        // Storage Info
        final totalStorageBytes = raw['storageTotal'] ?? 0;
        final storageDisplay = _getStorageDisplay(totalStorageBytes);

        // Display Info
        final List<dynamic> wList = raw['resWidth'] is List ? raw['resWidth'] : [raw['resWidth']];
        final List<dynamic> hList = raw['resHeight'] is List ? raw['resHeight'] : [raw['resHeight']];
        final List<dynamic> hzList = raw['resRefresh'] is List ? raw['resRefresh'] : [raw['resRefresh']];
        final displayDisplay = _formatDisplayResolution(wList, hList, hzList);

        return _cachedSpecs = SystemSpecs(
          brand: brandClean,
          model: modelClean,
          processor: cpuName,
          cores: raw['cores'] ?? 4,
          threads: raw['threads'] ?? 8,
          gen: gen,
          vendor: vendor,
          ram: ramDisplay,
          ramType: ramTypeDisplay,
          gpu: gpuClean,
          storage: storageDisplay,
          display: displayDisplay,
          os: raw['os'] ?? 'Windows 11',
        );
      }
    } catch (e) {
      debugPrint('Error al recopilar telemetria: $e');
    }

    return _cachedSpecs = _getDefaultFallback();
  }

  SystemSpecs _getDefaultFallback() {
    return SystemSpecs(
      brand: 'PC Generico',
      model: 'PC Desktop',
      processor: 'Intel Core i5',
      cores: 4,
      threads: 8,
      gen: '12th Gen',
      vendor: 'Intel',
      ram: '16GB',
      ramType: 'DDR4',
      gpu: 'Gráficos Integrados',
      storage: '512GB SSD',
      display: '1920 x 1080 (Full HD)',
      os: 'Windows 11 Home',
    );
  }

  String _cleanBrandName(String brand) {
    brand = brand.trim();
    final lower = brand.toLowerCase();
    if (lower.contains('asus')) return 'ASUS';
    if (lower.contains('hp') || lower.contains('hewlett-packard')) return 'HP';
    if (lower.contains('samsung')) return 'Samsung';
    if (lower.contains('lenovo')) return 'Lenovo';
    if (lower.contains('acer')) return 'Acer';
    if (lower.contains('dell')) return 'Dell';
    return brand;
  }

  bool _isGenericInfo(String brand, String model) {
    final b = brand.toLowerCase();
    final m = model.toLowerCase();
    return b.isEmpty || b.contains('generico') || b.contains('o.e.m') || b.contains('system product') || m.contains('system product') || m.contains('to be filled');
  }

  String _refineModelName(String brand, String model) {
    model = model.trim();
    // Eliminar la marca si ya está duplicada en el nombre del modelo
    if (model.toLowerCase().startsWith(brand.toLowerCase())) {
      model = model.substring(brand.length).trim();
    }
    // Eliminar textos basura de placa base
    model = model.replaceAll(RegExp(r'Default string|To be filled by O.E.M.', caseSensitive: false), '').trim();
    if (model.isEmpty) return 'Notebook';
    return model;
  }

  String _detectCpuGeneration(String cpuName) {
    cpuName = cpuName.toLowerCase();
    
    // 1. AMD Ryzen
    if (cpuName.contains('ryzen')) {
      final match = RegExp(r'ryzen\s+\d+\s+(\d)\d{3}').firstMatch(cpuName);
      if (match != null) {
        final familyDigit = match.group(1);
        switch (familyDigit) {
          case '3': return 'Ryzen 3000';
          case '4': return 'Ryzen 4000';
          case '5': return 'Ryzen 5000';
          case '6': return 'Ryzen 6000';
          case '7': return 'Ryzen 7000';
          case '8': return 'Ryzen 8000';
          case '9': return 'Ryzen 9000';
        }
      }
      if (cpuName.contains('ai')) return 'Ryzen AI';
      return 'Ryzen';
    }
    
    // 2. Intel Core Ultra
    if (cpuName.contains('ultra')) {
      return 'Core Ultra';
    }

    // 3. Intel Core (i9/i7/i5/i3)
    if (cpuName.contains('intel') && cpuName.contains('core')) {
      final match = RegExp(r'i\d[- ](\d{2})').firstMatch(cpuName);
      if (match != null) {
        return '${match.group(1)}th Gen';
      }
      final matchSingle = RegExp(r'i\d[- ](\d)').firstMatch(cpuName);
      if (matchSingle != null) {
        return '${matchSingle.group(1)}th Gen';
      }
    }

    // 4. Snapdragon
    if (cpuName.contains('snapdragon') || cpuName.contains('x elite') || cpuName.contains('x plus')) {
      return 'Snapdragon X';
    }

    return 'Desconocida';
  }

  String _getRamDisplay(int bytes) {
    if (bytes <= 0) return '8GB';
    final gb = bytes / (1024 * 1024 * 1024);
    // Redondear a la potencia comercial de 2 más cercana o valor entero estándar
    final rounded = gb.round();
    if (rounded <= 4) return '4GB';
    if (rounded <= 8) return '8GB';
    if (rounded <= 12) return '12GB';
    if (rounded <= 16) return '16GB';
    if (rounded <= 24) return '24GB';
    if (rounded <= 32) return '32GB';
    if (rounded <= 64) return '64GB';
    return '${rounded}GB';
  }

  String _detectRamType(List<dynamic> smbiosTypes, List<dynamic> speeds) {
    var type = 'DDR4';
    if (smbiosTypes.isNotEmpty) {
      final t = smbiosTypes.first;
      final int val = t is int ? t : int.tryParse(t.toString()) ?? 0;
      switch (val) {
        case 20: type = 'DDR'; break;
        case 21:
        case 22: type = 'DDR2'; break;
        case 24: type = 'DDR3'; break;
        case 26: type = 'DDR4'; break;
        case 29: type = 'LPDDR3'; break;
        case 30:
        case 31: type = 'LPDDR4'; break;
        case 34: type = 'DDR5'; break;
        case 35: type = 'LPDDR5'; break;
      }
    }

    var speed = 0;
    if (speeds.isNotEmpty) {
      final s = speeds.first;
      speed = s is int ? s : int.tryParse(s.toString()) ?? 0;
    }

    if (type == 'LPDDR5' && speed >= 6000) {
      type = 'LPDDR5X';
    }

    if (speed > 0) {
      return '$type - $speed MT/s';
    }
    return type;
  }

  String _detectBestGpu(List<String> gpus) {
    var bestGpu = 'Gráficos Integrados';
    var bestScore = 0;

    for (var rawGpu in gpus) {
      final clean = rawGpu.trim();
      final score = _rateGpu(clean);
      if (score > bestScore) {
        bestScore = score;
        bestGpu = clean;
      }
    }

    // Si es NVIDIA, intentar buscar el Wattage (TGP)
    if (bestScore >= 10) {
      final watts = _getNvidiaWatts();
      if (watts != null) {
        bestGpu = '$bestGpu ${watts}W';
      }
    }

    return bestGpu;
  }

  int _rateGpu(String name) {
    final up = name.toUpperCase();
    if (up.contains('NVIDIA') || up.contains('RTX') || up.contains('GTX')) return 10;
    if (up.contains('RX ') || up.contains('RX6') || up.contains('RX7') || up.contains('RX5') || up.contains('RX4')) return 8;
    if (up.contains('ARC')) return 5;
    if (up.contains('UHD') || up.contains('RADEON') || up.contains('IRIS') || up.contains('INTEL') || up.contains('AMD')) return 2;
    return 1;
  }

  String? _getNvidiaWatts() {
    try {
      final script = r'''
        $val = (nvidia-smi -q -d POWER | Select-String "Max Power Limit" | Where-Object { $_ -notmatch "N/A" });
        if ($val) { [int][float]($val.ToString().Split(':')[1].Replace('W','').Trim()) }
      ''';
      final result = Process.runSync('powershell', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', script]);
      if (result.exitCode == 0) {
        final stdout = result.stdout.toString().trim();
        if (stdout.isNotEmpty && RegExp(r'^\d+$').hasMatch(stdout)) {
          return stdout;
        }
      }
    } catch (_) {}
    return null;
  }

  String _getStorageDisplay(int totalBytes) {
    if (totalBytes <= 0) return '512GB SSD';
    final gb = totalBytes / (1024 * 1024 * 1024);
    
    // Redondear a tamaños comerciales estándar
    if (gb <= 128) return '128GB SSD';
    if (gb <= 256) return '256GB SSD';
    if (gb <= 512) return '512GB SSD';
    if (gb <= 1024) return '1TB SSD';
    if (gb <= 2048) return '2TB SSD';
    
    return '${gb.round()}GB SSD';
  }

  String _formatDisplayResolution(List<dynamic> widths, List<dynamic> heights, List<dynamic> refreshRates) {
    var maxW = 0;
    var maxH = 0;
    var maxHz = 0;

    for (var i = 0; i < widths.length; i++) {
      if (widths[i] == null) continue;
      final int w = widths[i] is int ? widths[i] : int.tryParse(widths[i].toString()) ?? 0;
      final int h = (heights.length > i && heights[i] != null) ? (heights[i] is int ? heights[i] : int.tryParse(heights[i].toString()) ?? 0) : 0;
      final int hz = (refreshRates.length > i && refreshRates[i] != null) ? (refreshRates[i] is int ? refreshRates[i] : int.tryParse(refreshRates[i].toString()) ?? 0) : 0;
      
      if (w > maxW) {
        maxW = w;
        maxH = h;
        maxHz = hz;
      }
    }

    if (maxW == 0) {
      maxW = 1920;
      maxH = 1080;
    }

    var label = '';
    if (maxW == 1920 && maxH == 1080) {
      label = ' (Full HD)';
    } else if (maxW == 1920 && maxH == 1200) {
      label = ' (WUXGA)';
    } else if (maxW == 2560 && maxH == 1440) {
      label = ' (2K QHD)';
    } else if (maxW == 2560 && maxH == 1600) {
      label = ' (QHD+)';
    } else if (maxW == 2880 && maxH == 1800) {
      label = ' (2.8K)';
    } else if (maxW == 3000 && maxH == 2000) {
      label = ' (3K)';
    } else if (maxW == 3200 && maxH == 2000) {
      label = ' (3.2K)';
    } else if (maxW == 3840 && maxH == 2160) {
      label = ' (4K UHD)';
    } else if (maxW == 3840 && maxH == 2400) {
      label = ' (UHD+)';
    } else if (maxW == 1366 && maxH == 768) {
      label = ' (HD)';
    }

    if (maxHz > 0) {
      final hzVal = _approximateRefreshRate(maxHz);
      return '$maxW x $maxH$label - ${hzVal}Hz';
    }
    return '$maxW x $maxH$label';
  }

  int _approximateRefreshRate(int hz) {
    const commercialRates = [60, 75, 90, 100, 120, 144, 165, 240, 360, 480, 540];
    var closest = hz;
    var minDiff = 999999;
    for (var r in commercialRates) {
      final diff = (hz - r).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = r;
      }
    }
    if (minDiff <= 10) return closest;
    return hz;
  }
}
