<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');

// Folder tempat menyimpan file JSON soal
$game_folder = '/root/game/';

// Pastikan folder ada
if (!file_exists($game_folder)) {
    mkdir($game_folder, 0755, true);
}

// Handle OPTIONS request untuk CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// GET: Ambil daftar file atau isi file
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    
    // Jika ada parameter 'file', ambil isi file tersebut
    if (isset($_GET['file'])) {
        $filename = basename($_GET['file']); // Sanitasi nama file
        $filepath = $game_folder . $filename;
        
        if (file_exists($filepath) && pathinfo($filepath, PATHINFO_EXTENSION) === 'json') {
            $content = file_get_contents($filepath);
            $json_data = json_decode($content, true);
            
            if ($json_data === null) {
                http_response_code(400);
                echo json_encode([
                    'success' => false,
                    'message' => 'File JSON tidak valid'
                ]);
                exit;
            }
            
            echo json_encode([
                'success' => true,
                'filename' => $filename,
                'data' => $json_data,
                'count' => count($json_data)
            ]);
        } else {
            http_response_code(404);
            echo json_encode([
                'success' => false,
                'message' => 'File tidak ditemukan'
            ]);
        }
        exit;
    }
    
    // Jika tidak ada parameter, ambil daftar semua file JSON
    $files = [];
    $dir_files = scandir($game_folder);
    
    foreach ($dir_files as $file) {
        if ($file !== '.' && $file !== '..' && pathinfo($file, PATHINFO_EXTENSION) === 'json') {
            $filepath = $game_folder . $file;
            $size = filesize($filepath);
            $modified = filemtime($filepath);
            
            // Coba hitung jumlah soal
            $question_count = 0;
            $content = file_get_contents($filepath);
            $json_data = json_decode($content, true);
            if (is_array($json_data)) {
                $question_count = count($json_data);
            }
            
            $files[] = [
                'name' => $file,
                'size' => $size,
                'size_formatted' => formatBytes($size),
                'modified' => date('Y-m-d H:i:s', $modified),
                'question_count' => $question_count
            ];
        }
    }
    
    // Urutkan berdasarkan nama
    usort($files, function($a, $b) {
        return strcmp($a['name'], $b['name']);
    });
    
    echo json_encode([
        'success' => true,
        'folder' => $game_folder,
        'files' => $files,
        'total_files' => count($files)
    ]);
    exit;
}

// POST: Upload file JSON baru ke folder
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (!isset($data['filename']) || !isset($data['content'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Parameter tidak lengkap (filename dan content diperlukan)'
        ]);
        exit;
    }
    
    $filename = basename($data['filename']); // Sanitasi nama file
    
    // Pastikan ekstensi .json
    if (pathinfo($filename, PATHINFO_EXTENSION) !== 'json') {
        $filename .= '.json';
    }
    
    $filepath = $game_folder . $filename;
    
    // Validasi JSON
    $json_content = json_encode($data['content'], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    if ($json_content === false) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Data JSON tidak valid'
        ]);
        exit;
    }
    
    // Simpan file
    $result = file_put_contents($filepath, $json_content);
    
    if ($result !== false) {
        echo json_encode([
            'success' => true,
            'message' => 'File berhasil disimpan',
            'filename' => $filename,
            'path' => $filepath,
            'size' => $result
        ]);
    } else {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'message' => 'Gagal menyimpan file'
        ]);
    }
    exit;
}

// DELETE: Hapus file
if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    parse_str(file_get_contents('php://input'), $_DELETE);
    
    if (!isset($_DELETE['file'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Parameter file diperlukan'
        ]);
        exit;
    }
    
    $filename = basename($_DELETE['file']);
    $filepath = $game_folder . $filename;
    
    if (file_exists($filepath) && pathinfo($filepath, PATHINFO_EXTENSION) === 'json') {
        if (unlink($filepath)) {
            echo json_encode([
                'success' => true,
                'message' => 'File berhasil dihapus',
                'filename' => $filename
            ]);
        } else {
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'message' => 'Gagal menghapus file'
            ]);
        }
    } else {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'message' => 'File tidak ditemukan'
        ]);
    }
    exit;
}

// Helper function untuk format ukuran file
function formatBytes($bytes, $precision = 2) {
    $units = ['B', 'KB', 'MB', 'GB'];
    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);
    $bytes /= pow(1024, $pow);
    return round($bytes, $precision) . ' ' . $units[$pow];
}

http_response_code(405);
echo json_encode([
    'success' => false,
    'message' => 'Method not allowed'
]);
?>