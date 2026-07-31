class DefaultAvatarOption {
  const DefaultAvatarOption({required this.assetPath, required this.labelKey});

  final String assetPath;
  final String labelKey;
}

const List<DefaultAvatarOption> defaultAvatarCatalog = <DefaultAvatarOption>[
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_cat_orange_tabby.png',
    labelKey: 'defaultAvatarOrangeTabby',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_cat_brown_tabby.png',
    labelKey: 'defaultAvatarBrownTabby',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_cat_tuxedo.png',
    labelKey: 'defaultAvatarTuxedoCat',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_cat_siamese.png',
    labelKey: 'defaultAvatarSiameseCat',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_dog.png',
    labelKey: 'defaultAvatarHackerDog',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_dog_shiba.png',
    labelKey: 'defaultAvatarShiba',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_dog_corgi.png',
    labelKey: 'defaultAvatarCorgi',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hacker_dog_doberman.png',
    labelKey: 'defaultAvatarDoberman',
  ),
  DefaultAvatarOption(
    assetPath: 'assets/images/default_avatars/hitcon_hat.png',
    labelKey: 'defaultAvatarHitconHat',
  ),
];
