using Godot;
using System;
using System.IO;

public partial class ProjectScanner : Node
{
	// === СИГНАЛЫ ===
	[Signal]
	public delegate void ScanCompletedEventHandler(int folderCount, int fileCount);

	[Signal]
	public delegate void LineCountCompletedEventHandler(int nonEmptyScriptFileCount, int totalScriptLineCount);

	[Signal]
	public delegate void SceneStatsCompletedEventHandler(int sceneCount, long projectSizeBytes);

	// === НАСТРОЙКИ ===
	[Export]
	public string[] ExcludedFolders { get; set; } = {
		".git", ".godot", ".mono", "bin", "obj", "shader_cache",
		"temp", "metadata", "Debug", "ref", "refint", "builds"
	};

	[Export]
	public string[] TargetExtensions { get; set; } = { ".gd", ".cs", ".gdshader" };

	// === СЧЁТЧИКИ ===
	private int totalFolders = 0;
	private int totalFiles = 0;
	private int scriptFileCount = 0;
	private int scriptLineCount = 0;
	private int sceneFileCount = 0;
	private long totalProjectSizeBytes = 0;

	public override void _Ready()
	{
		CallDeferred(nameof(StartScan));
	}

	public void StartScan()
	{
		// Сброс
		totalFolders = 0;
		totalFiles = 0;
		scriptFileCount = 0;
		scriptLineCount = 0;
		sceneFileCount = 0;
		totalProjectSizeBytes = 0;

		string rootPath = ProjectSettings.GlobalizePath("res://");
		ScanDirectoryRecursive(rootPath);

		EmitSignal("ScanCompleted", totalFolders, totalFiles);
		EmitSignal("LineCountCompleted", scriptFileCount, scriptLineCount);
		EmitSignal("SceneStatsCompleted", sceneFileCount, totalProjectSizeBytes);
	}

	private void ScanDirectoryRecursive(string directoryPath)
	{
		try
		{
			foreach (string subdirectory in Directory.GetDirectories(directoryPath))
			{
				string folderName = Path.GetFileName(subdirectory);
				if (IsFolderExcluded(folderName))
					continue;

				totalFolders++;
				ScanDirectoryRecursive(subdirectory);
			}

			foreach (string filePath in Directory.GetFiles(directoryPath))
			{
				string fileName = Path.GetFileName(filePath);
				string ext = Path.GetExtension(filePath).ToLowerInvariant();

				// Пропускаем временные и служебные файлы
				if (fileName.EndsWith(".import") || fileName.EndsWith(".tmp") || fileName == ".DS_Store")
					continue;

				totalFiles++;

				// Подсчёт размера файла
				try
				{
					FileInfo info = new FileInfo(filePath);
					totalProjectSizeBytes += info.Length;
				}
				catch (Exception ex)
				{
					GD.PrintErr($"⚠️ Не удалось получить размер '{filePath}': {ex.Message}");
				}

				// Подсчёт сцен
				if (ext == ".tscn")
				{
					sceneFileCount++;
				}

				// Подсчёт строк в скриптах
				if (!Array.Exists(TargetExtensions, e => e == ext))
					continue;

				try
				{
					string[] lines = File.ReadAllLines(filePath);
					int validLines = 0;

					foreach (string line in lines)
					{
						string trimmed = line.Trim();

						if (string.IsNullOrEmpty(trimmed))
							continue;

						if (ext == ".gd" || ext == ".gdshader")
						{
							if (trimmed.StartsWith("#"))
								continue;
						}
						else if (ext == ".cs")
						{
							if (trimmed.StartsWith("//"))
								continue;
						}

						validLines++;
					}

					if (validLines > 0)
						scriptFileCount++;

					scriptLineCount += validLines;
				}
				catch (Exception ex)
				{
					GD.PrintErr($"❌ Ошибка при чтении '{filePath}': {ex.Message}");
				}
			}
		}
		catch (Exception ex)
		{
			GD.PrintErr($"❌ Ошибка при сканировании '{directoryPath}': {ex.Message}");
		}
	}

	private bool IsFolderExcluded(string folderName)
	{
		foreach (string excluded in ExcludedFolders)
		{
			if (folderName.Equals(excluded, StringComparison.OrdinalIgnoreCase))
				return true;
		}
		return false;
	}
}
