from pathlib import Path
import shutil
import tempfile
import unittest

from scripts.update_image import MANIFESTS, update_image


class UpdateImageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        shutil.copytree(Path(__file__).resolve().parents[1] / 'k8s', self.root / 'k8s')

    def snapshot(self):
        return {p.name: p.read_bytes() for p in (self.root / 'k8s').iterdir()}

    def test_each_service_changes_only_its_image_and_is_idempotent(self):
        for service, filename in MANIFESTS.items():
            with self.subTest(service=service):
                before = self.snapshot()
                image = f'gcrbr/{service}:' + 'a' * 40
                self.assertTrue(update_image(self.root, service, image))
                after = self.snapshot()
                self.assertEqual([name for name in before if before[name] != after[name]], [filename])
                old_lines = before[filename].decode().splitlines()
                new_lines = after[filename].decode().splitlines()
                self.assertEqual(len(old_lines), len(new_lines))
                changes = [(old, new) for old, new in zip(old_lines, new_lines) if old != new]
                self.assertEqual(len(changes), 1)
                self.assertEqual(changes[0][1].strip(), f'image: {image}')
                self.assertFalse(update_image(self.root, service, image))
                self.assertEqual(after, self.snapshot())

    def test_invalid_input_never_changes_files(self):
        before = self.snapshot()
        for service, image in [
            ('database', 'gcrbr/backend:' + 'a' * 40),
            ('backend', 'gcrbr/frontend:' + 'a' * 40),
            ('backend', 'gcrbr/backend:latest'),
            ('backend', 'gcrbr/backend:' + 'a' * 39),
            ('backend', 'gcrbr/backend:' + 'a' * 40 + '\n'),
            ('backend', 'attacker/backend:' + 'a' * 40),
        ]:
            with self.subTest(service=service, image=image):
                with self.assertRaises(ValueError):
                    update_image(self.root, service, image)
                self.assertEqual(before, self.snapshot())

    def test_unrelated_sidecar_and_inline_comment_are_preserved(self):
        path = self.root / 'k8s' / MANIFESTS['backend']
        content = path.read_text()
        content = content.replace('\n          ports:', ' # deployed image\n          ports:', 1)
        content += '\n        - name: sidecar\n          image: example/sidecar:stable\n'
        path.write_text(content)
        image = 'gcrbr/backend:' + 'b' * 40
        update_image(self.root, 'backend', image)
        self.assertIn(f'image: {image} # deployed image\n', path.read_text())
        self.assertIn('image: example/sidecar:stable\n', path.read_text())

    def test_ambiguous_or_changed_layout_is_rejected_without_writing(self):
        path = self.root / 'k8s' / MANIFESTS['backend']
        original = path.read_text()
        for content in [original + '\n' + original, original.replace('- name: backend', '- name: renamed')]:
            path.write_text(content)
            with self.assertRaises(ValueError):
                update_image(self.root, 'backend', 'gcrbr/backend:' + 'c' * 40)
            self.assertEqual(path.read_text(), content)


if __name__ == '__main__':
    unittest.main()
